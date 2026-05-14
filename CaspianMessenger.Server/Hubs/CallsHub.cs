using System.Security.Claims;
using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Hubs;

// ── DTOs (client sends these as single-argument objects) ────────────────────

public sealed record StartCallDto(
    string CallId,
    List<string> TargetUserIds,
    bool IsVideo,
    bool IsGroup = false,
    string? ChatId = null);

public sealed record SendOfferDto(
    string CallId,
    string TargetUserId,
    string Sdp,
    string Type);

public sealed record SendAnswerDto(
    string CallId,
    string TargetUserId,
    string Sdp,
    string Type);

public sealed record SendIceCandidateDto(
    string CallId,
    string TargetUserId,
    string Candidate,
    string SdpMid,
    int SdpMLineIndex);

// ── Hub ──────────────────────────────────────────────────────────────────────

[Authorize]
public class CallsHub(
    CallService callService,
    FcmService fcmService,
    AppDbContext db,
    ILogger<CallsHub> logger) : Hub
{
    // ── Lifecycle ─────────────────────────────────────────────────────────────

    /// При подключении добавляем клиента в персональную группу userId.
    /// Это зеркалит поведение ChatHub и позволяет Clients.Group(userId)
    /// находить пользователя независимо от платформы (web/native).
    public override async Task OnConnectedAsync()
    {
        var userId = GetUserId();
        if (userId != Guid.Empty)
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, userId.ToString());
            logger.LogDebug("CallsHub: user {UserId} connected ({ConnId})", userId, Context.ConnectionId);
        }
        await base.OnConnectedAsync();
    }

    // ── Client → Server ──────────────────────────────────────────────────────

    /// Инициирует звонок. Клиент передаёт один объект StartCallDto.
    public async Task StartCall(StartCallDto dto)
    {
        var callerId = GetUserId();
        if (callerId == Guid.Empty) return;
        if (string.IsNullOrWhiteSpace(dto.CallId)) return;

        if (await db.Users.FindAsync(callerId) == null) return;

        // callId используется как строковый ключ группы SignalR.
        // Для CallService нужен Guid — берём из callId если это валидный UUID,
        // иначе генерируем новый (не критично, только для in-memory учёта).
        var callGuid = Guid.TryParse(dto.CallId, out var g) ? g : Guid.NewGuid();

        var callerName = await GetDisplayNameAsync(callerId);

        await callService.CreateCallAsync(callGuid, callerId.ToString(), dto.IsVideo, dto.IsGroup);
        await Groups.AddToGroupAsync(Context.ConnectionId, dto.CallId);

        var payload = new
        {
            callId      = dto.CallId,
            callerId    = callerId.ToString(),
            callerName,
            isVideo     = dto.IsVideo,
            isGroup     = dto.IsGroup,
        };

        // Уведомляем каждого адресата.
        // Используем Clients.Group(userId) вместо Clients.User(userId) — это
        // зеркалит подход NotificationService и работает надёжно на всех
        // платформах (web/native), так как группа создаётся в OnConnectedAsync.
        foreach (var targetId in dto.TargetUserIds)
        {
            // SignalR (если онлайн)
            await Clients.Group(targetId).SendAsync("IncomingCall", payload);

            // FCM push на все устройства (если фон / закрыто приложение)
            await fcmService.SendCallNotificationAsync(
                targetId, dto.CallId, callerId.ToString(),
                callerName, dto.IsVideo, dto.IsGroup);
        }

        logger.LogInformation("Call {CallId} started by {CallerId}, targets: {Targets}",
            dto.CallId, callerId, string.Join(", ", dto.TargetUserIds));
    }

    /// Участник принимает звонок и входит в группу.
    public async Task JoinCall(string callId)
    {
        var userId = GetUserId();
        if (userId == Guid.Empty) return;
        if (string.IsNullOrWhiteSpace(callId)) return;

        await Groups.AddToGroupAsync(Context.ConnectionId, callId);

        // Обновляем in-memory состояние если callId — валидный UUID
        if (Guid.TryParse(callId, out var callGuid))
            await callService.JoinCallAsync(callGuid, userId.ToString());

        var joinName = await GetDisplayNameAsync(userId);
        await Clients.OthersInGroup(callId).SendAsync("ParticipantJoined", new
        {
            callId,
            userId = userId.ToString(),
            name   = joinName,
        });

        logger.LogInformation("User {UserId} joined call {CallId}", userId, callId);
    }

    /// Участник покидает звонок.
    public async Task LeaveCall(string callId)
    {
        var userId = GetUserId();
        if (userId == Guid.Empty) return;
        if (string.IsNullOrWhiteSpace(callId)) return;

        await Groups.RemoveFromGroupAsync(Context.ConnectionId, callId);

        bool callEnded = false;
        if (Guid.TryParse(callId, out var callGuid))
            (callEnded, _) = await callService.LeaveCallAsync(callGuid, userId.ToString());

        if (callEnded)
            await Clients.Group(callId).SendAsync("CallEnded", new { callId });
        else
        {
            var leaveName = await GetDisplayNameAsync(userId);
            await Clients.Group(callId).SendAsync("ParticipantLeft", new
            {
                callId,
                userId = userId.ToString(),
                name   = leaveName,
            });
        }

        logger.LogInformation("User {UserId} left call {CallId} (ended={Ended})", userId, callId, callEnded);
    }

    // ── WebRTC signal proxying ────────────────────────────────────────────────

    /// Проксирует SDP-offer к целевому пользователю. Включает type (offer/pranswer/rollback).
    public async Task SendOffer(SendOfferDto dto)
    {
        var senderId = GetUserId();
        if (senderId == Guid.Empty) return;

        await Clients.Group(dto.TargetUserId).SendAsync("ReceiveOffer", new
        {
            callId     = dto.CallId,
            fromUserId = senderId.ToString(),
            sdp        = dto.Sdp,
            type       = dto.Type,
        });
    }

    /// Проксирует SDP-answer к целевому пользователю. Включает type (answer).
    public async Task SendAnswer(SendAnswerDto dto)
    {
        var senderId = GetUserId();
        if (senderId == Guid.Empty) return;

        await Clients.Group(dto.TargetUserId).SendAsync("ReceiveAnswer", new
        {
            callId     = dto.CallId,
            fromUserId = senderId.ToString(),
            sdp        = dto.Sdp,
            type       = dto.Type,
        });
    }

    /// Проксирует ICE-кандидата. Сохраняет sdpMid и sdpMLineIndex — обязательны для RTCIceCandidate.
    public async Task SendIceCandidate(SendIceCandidateDto dto)
    {
        var senderId = GetUserId();
        if (senderId == Guid.Empty) return;

        await Clients.Group(dto.TargetUserId).SendAsync("ReceiveIceCandidate", new
        {
            callId       = dto.CallId,
            fromUserId   = senderId.ToString(),
            candidate    = dto.Candidate,
            sdpMid       = dto.SdpMid,
            sdpMLineIndex = dto.SdpMLineIndex,
        });
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var userId = GetUserId();
        if (userId != Guid.Empty)
        {
            await Groups.RemoveFromGroupAsync(Context.ConnectionId, userId.ToString());
            logger.LogDebug("CallsHub: user {UserId} disconnected ({ConnId})", userId, Context.ConnectionId);
            var userIdStr = userId.ToString();
            var displayName = await GetDisplayNameAsync(userId);

            foreach (var call in callService.GetUserActiveCalls(userIdStr).ToList())
            {
                var callIdStr = call.Id.ToString();
                var (callEnded, _) = await callService.LeaveCallAsync(call.Id, userIdStr);
                if (callEnded)
                    await Clients.Group(callIdStr).SendAsync("CallEnded", new { callId = callIdStr });
                else
                    await Clients.Group(callIdStr).SendAsync("ParticipantLeft", new
                    {
                        callId = callIdStr,
                        userId = userIdStr,
                        name   = displayName,
                    });
            }
        }
        await base.OnDisconnectedAsync(exception);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private Guid GetUserId()
    {
        var sub = Context.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value
                  ?? Context.User?.FindFirst("sub")?.Value;
        return Guid.TryParse(sub, out var id) ? id : Guid.Empty;
    }

    private async Task<string> GetDisplayNameAsync(Guid userId)
    {
        var person = await db.People.FirstOrDefaultAsync(p => p.UserId == userId);
        if (person != null)
        {
            var parts = new[] { person.LastName, person.FirstName, person.MiddleName }
                .Where(p => !string.IsNullOrWhiteSpace(p));
            return string.Join(" ", parts);
        }
        var user = await db.Users.FindAsync(userId);
        return user?.Name ?? userId.ToString();
    }
}
