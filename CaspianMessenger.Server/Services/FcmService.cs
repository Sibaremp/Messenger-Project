using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.Models;
using FirebaseAdmin;
using FirebaseAdmin.Messaging;
using FcmMessage = FirebaseAdmin.Messaging.Message;
using FirebaseNotification = FirebaseAdmin.Messaging.Notification;
using Google.Apis.Auth.OAuth2;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Services;

/// <summary>
/// Singleton-сервис для отправки Firebase Cloud Messaging push-уведомлений.
/// Поддерживает несколько устройств на пользователя, batch-отправку,
/// автоматическую очистку невалидных токенов и retry при временных ошибках.
/// </summary>
public class FcmService
{
    private readonly bool _enabled;
    private readonly ILogger<FcmService> _logger;
    private readonly IServiceScopeFactory _scopeFactory;

    // Коды ошибок FCM, при которых токен нужно удалить
    private static readonly MessagingErrorCode[] InvalidTokenCodes =
    [
        MessagingErrorCode.Unregistered,
        MessagingErrorCode.SenderIdMismatch
    ];

    // Коды, при которых имеет смысл повторить отправку
    private static readonly MessagingErrorCode[] TransientCodes =
    [
        MessagingErrorCode.Internal,
        MessagingErrorCode.Unavailable,
        MessagingErrorCode.QuotaExceeded
    ];

    public FcmService(IConfiguration config, ILogger<FcmService> logger, IServiceScopeFactory scopeFactory)
    {
        _logger = logger;
        _scopeFactory = scopeFactory;

        var credPath = config["Firebase:CredentialsPath"];
        if (string.IsNullOrWhiteSpace(credPath) || !File.Exists(credPath))
        {
            _logger.LogWarning("Firebase credentials not found at '{Path}'. FCM disabled.", credPath);
            return;
        }

        try
        {
            if (FirebaseApp.DefaultInstance == null)
                FirebaseApp.Create(new AppOptions { Credential = GoogleCredential.FromFile(credPath) });

            _enabled = true;
            _logger.LogInformation("Firebase initialized successfully");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Firebase initialization failed");
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /// <summary>
    /// Отправляет push на все зарегистрированные устройства пользователя.
    /// </summary>
    public async Task SendAsync(string userId, Dictionary<string, string> data)
    {
        if (!_enabled) return;
        if (!Guid.TryParse(userId, out var userGuid)) return;

        var tokens = await GetUserTokensAsync(userGuid);
        if (tokens.Count == 0) return;

        await SendToMultipleAsync(tokens.Select(d => d.FcmToken).ToList(), data);
    }

    /// <summary>
    /// Batch-отправка по явному списку FCM-токенов (до 500 за раз).
    /// </summary>
    public async Task SendToMultipleAsync(List<string> tokens, Dictionary<string, string> data)
    {
        if (!_enabled || tokens.Count == 0) return;

        // FCM поддерживает max 500 сообщений в одном batch
        foreach (var chunk in tokens.Distinct().Chunk(500))
        {
            var messages = chunk.Select(t => BuildMessage(t, data)).ToList();
            await SendBatchWithRetryAsync([.. chunk], messages);
        }
    }

    /// <summary>
    /// Регистрирует или обновляет FCM-токен для пользователя.
    /// Один и тот же токен не может принадлежать двум пользователям одновременно.
    /// </summary>
    public async Task RegisterTokenAsync(Guid userId, string token, string platform)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var existing = await db.UserDevices.FirstOrDefaultAsync(d => d.FcmToken == token);
        if (existing != null)
        {
            existing.UserId    = userId;
            existing.Platform  = platform;
            existing.UpdatedAt = DateTime.UtcNow;
        }
        else
        {
            db.UserDevices.Add(new UserDevice
            {
                UserId    = userId,
                FcmToken  = token,
                Platform  = platform,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            });
        }

        await db.SaveChangesAsync();
        _logger.LogDebug("FCM token registered for user {UserId} [{Platform}]", userId, platform);
    }

    // ── Backward-compat helpers ───────────────────────────────────────────────

    /// <summary>Отправляет push о входящем звонке по userId (ищет все устройства).</summary>
    public Task SendCallNotificationAsync(
        string userId, string callId, string callerId, string callerName,
        bool isVideo, bool isGroup) =>
        SendAsync(userId, NotificationPayload.Call(callId, callerId, callerName, isVideo, isGroup));

    // ── Private helpers ───────────────────────────────────────────────────────

    private static FcmMessage BuildMessage(string token, Dictionary<string, string> data)
    {
        // Для сообщений добавляем notification-блок, чтобы система сама
        // показала уведомление когда приложение в фоне или закрыто.
        // В foreground Firebase передаёт сообщение в onMessage (не в трее),
        // поэтому дублей не будет — Flutter показывает своё локальное уведомление.
        FirebaseNotification? notification = null;
        AndroidNotification? androidNotif = null;
        ApnsConfig apns = new() { Headers = new Dictionary<string, string> { ["apns-priority"] = "10" } };

        if (data.TryGetValue("type", out var msgType))
        {
            if (msgType == "message")
            {
                var title = data.GetValueOrDefault("senderName", "Новое сообщение");
                var body  = data.GetValueOrDefault("text", "");
                notification = new FirebaseNotification { Title = title, Body = body };
                androidNotif = new AndroidNotification { ChannelId = "messages_channel" };
            }
            else if (msgType == "admin_notification")
            {
                var title = data.GetValueOrDefault("title", "Уведомление");
                var body  = data.GetValueOrDefault("body", "");
                notification = new FirebaseNotification { Title = title, Body = body };
                androidNotif = new AndroidNotification { ChannelId = "system_channel" };
            }
        }

        return new FcmMessage
        {
            Token        = token,
            Data         = data,
            Notification = notification,
            Android      = new AndroidConfig
            {
                Priority     = Priority.High,
                Notification = androidNotif,
            },
            Apns = apns,
        };
    }

    private async Task SendBatchWithRetryAsync(List<string> tokens, List<FcmMessage> messages, int attempt = 0)
    {
        try
        {
            var response = await FirebaseMessaging.DefaultInstance.SendEachAsync(messages);

            // Обрабатываем результат по каждому токену
            var tokensToDelete = new List<string>();
            for (var i = 0; i < response.Responses.Count; i++)
            {
                var result = response.Responses[i];
                if (result.IsSuccess) continue;

                var code = result.Exception?.MessagingErrorCode;
                if (code.HasValue && InvalidTokenCodes.Contains(code.Value))
                {
                    tokensToDelete.Add(tokens[i]);
                    _logger.LogDebug("Removing invalid FCM token (code={Code})", code);
                }
                else
                {
                    _logger.LogWarning("FCM send failed for token[{I}]: {Code} — {Msg}",
                        i, code, result.Exception?.Message);
                }
            }

            if (tokensToDelete.Count > 0)
                await RemoveTokensAsync(tokensToDelete);
        }
        catch (FirebaseMessagingException ex)
            when (attempt < 2 && ex.MessagingErrorCode.HasValue &&
                  TransientCodes.Contains(ex.MessagingErrorCode.Value))
        {
            var delay = TimeSpan.FromSeconds(Math.Pow(2, attempt)); // 1s, 2s
            _logger.LogWarning("FCM transient error ({Code}), retry {N} in {Delay}s",
                ex.MessagingErrorCode, attempt + 1, delay.TotalSeconds);
            await Task.Delay(delay);
            await SendBatchWithRetryAsync(tokens, messages, attempt + 1);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "FCM batch send failed (attempt {N})", attempt + 1);
        }
    }

    private async Task<List<UserDevice>> GetUserTokensAsync(Guid userId)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        return await db.UserDevices.Where(d => d.UserId == userId).ToListAsync();
    }

    private async Task RemoveTokensAsync(List<string> tokens)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var devices = await db.UserDevices
            .Where(d => tokens.Contains(d.FcmToken))
            .ToListAsync();
        db.UserDevices.RemoveRange(devices);
        await db.SaveChangesAsync();
        _logger.LogInformation("Removed {Count} invalid FCM token(s)", devices.Count);
    }
}
