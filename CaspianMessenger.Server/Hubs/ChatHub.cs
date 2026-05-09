using System.Security.Claims;
using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.Helpers;
using CaspianMessenger.Server.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;

namespace CaspianMessenger.Server.Hubs;

[Authorize]
public class ChatHub(AppDbContext db, MessageService messageService, ILogger<ChatHub> logger, IMemoryCache cache) : Hub
{
    public override async Task OnConnectedAsync()
    {
        var userId = GetUserId();
        if (userId == Guid.Empty) return;

        await Groups.AddToGroupAsync(Context.ConnectionId, userId.ToString());

        var token = Context.GetHttpContext()?.Request.Query["access_token"].ToString();
        if (!string.IsNullOrEmpty(token))
        {
            var tokenHash = TokenHashHelper.ComputeSha256(token);
            await Groups.AddToGroupAsync(Context.ConnectionId, $"session_{tokenHash}");
            cache.Set($"conn_{Context.ConnectionId}", tokenHash, TimeSpan.FromHours(24));
        }
        await Groups.AddToGroupAsync(Context.ConnectionId, $"user_{userId}");

        var user = await db.Users.FindAsync(userId);
        if (user != null)
        {
            user.IsOnline = true;
            user.LastSeen = DateTime.UtcNow;
            await db.SaveChangesAsync();
        }

        logger.LogInformation("User {UserId} connected", userId);
        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var userId = GetUserId();
        if (userId == Guid.Empty) return;

        await Groups.RemoveFromGroupAsync(Context.ConnectionId, userId.ToString());
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"user_{userId}");

        if (cache.TryGetValue($"conn_{Context.ConnectionId}", out string? tokenHash) && tokenHash != null)
        {
            await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"session_{tokenHash}");
            cache.Remove($"conn_{Context.ConnectionId}");
        }

        var user = await db.Users.FindAsync(userId);
        if (user != null)
        {
            user.IsOnline = false;
            user.LastSeen = DateTime.UtcNow;
            await db.SaveChangesAsync();
        }

        logger.LogInformation("User {UserId} disconnected", userId);
        await base.OnDisconnectedAsync(exception);
    }

    public async Task SendEvent(object eventData)
    {
        // Client -> Server events handled here
    }

    public async Task MarkRead(Guid chatId, List<Guid> messageIds)
    {
        var userId = GetUserId();
        if (userId == Guid.Empty) return;
        await messageService.MarkMessagesReadAsync(userId, chatId, messageIds);
    }

    /// Клиент вызывает этот метод сразу при получении сообщения (message_received).
    /// Переводит статус из sent → delivered и уведомляет отправителя.
    public async Task MarkDelivered(Guid chatId, List<Guid> messageIds)
    {
        var userId = GetUserId();
        if (userId == Guid.Empty) return;
        await messageService.MarkMessagesDeliveredAsync(userId, chatId, messageIds);
    }

    private Guid GetUserId()
    {
        var sub = Context.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value
                  ?? Context.User?.FindFirst("sub")?.Value;
        return Guid.TryParse(sub, out var id) ? id : Guid.Empty;
    }
}
