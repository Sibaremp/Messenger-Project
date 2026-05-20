using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.DTOs.Chat;
using CaspianMessenger.Server.Hubs;
using CaspianMessenger.Server.Models;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Services;

public class NotificationService(
    IHubContext<ChatHub> hubContext,
    FcmService fcmService,
    AppDbContext db,
    EncryptionService encryption)
{
    // ── SignalR + FCM: новое сообщение ────────────────────────────────────────

    public async Task NotifyMessageReceived(List<Guid> memberIds, Guid chatId, MessageDto message)
    {
        // Определяем тип чата для FCM payload один раз
        var chat = await db.Chats.AsNoTracking().FirstOrDefaultAsync(c => c.Id == chatId);
        var isGroup = chat?.Type is "group" or "community";
        var chatName = isGroup ? chat?.Name : null;

        // Plaintext for FCM (push notification body is always readable)
        var plainText = message.Text;

        // Определяем тип вложения для уведомления
        var fcmText = string.IsNullOrWhiteSpace(plainText)
            ? GetAttachmentLabel(message.Attachments)
            : plainText;

        foreach (var memberId in memberIds)
        {
            // SignalR — шифруем текст для каждого получателя индивидуально
            var encText    = encryption.Encrypt(memberId, plainText);
            var encMessage = message.WithEncryptedText(encText);

            await hubContext.Clients.Group(memberId.ToString())
                .SendAsync("ReceiveEvent", new
                {
                    type = "message_received",
                    chatId,
                    message = encMessage
                });

            // FCM — только не автору; использует plaintext (пуш не шифруется)
            if (memberId == message.SenderId) continue;

            // Тип вложения для клиента (чтобы показать иконку)
            var attachmentType = message.Attachments.Count > 0
                ? message.Attachments[0].Type
                : null;

            await fcmService.SendAsync(memberId.ToString(),
                NotificationPayload.Message(
                    chatId:         chatId.ToString(),
                    senderId:       message.SenderId.ToString(),
                    senderName:     message.SenderName,
                    text:           fcmText,
                    avatarUrl:      message.SenderAvatarPath ?? "",
                    isGroup:        isGroup,
                    chatName:       chatName,
                    attachmentType: attachmentType));
        }
    }

    /// <summary>Возвращает читаемую метку для вложения в push-уведомлении.</summary>
    private static string GetAttachmentLabel(List<AttachmentDto> attachments)
    {
        if (attachments.Count == 0) return "[вложение]";
        var type = attachments[0].Type?.ToLowerInvariant() ?? "";
        return type switch
        {
            "image"  => "📷 Фото",
            "video"  => "🎥 Видео",
            "audio"  => "🎵 Голосовое сообщение",
            "voice"  => "🎵 Голосовое сообщение",
            "document" or "file" => "📎 Файл",
            _ => "[вложение]"
        };
    }

    // ── SignalR: остальные события ────────────────────────────────────────────

    public async Task NotifyMessageEdited(List<Guid> memberIds, Guid chatId, Guid messageId, string newText)
    {
        foreach (var memberId in memberIds)
        {
            var encText = encryption.Encrypt(memberId, newText);
            await hubContext.Clients.Group(memberId.ToString())
                .SendAsync("ReceiveEvent", new { type = "message_edited", chatId, messageId, newText = encText });
        }
    }

    public async Task NotifyMessagesDeleted(List<Guid> memberIds, Guid chatId, List<Guid> messageIds)
    {
        foreach (var memberId in memberIds)
            await hubContext.Clients.Group(memberId.ToString())
                .SendAsync("ReceiveEvent", new { type = "message_deleted", chatId, messageIds });
    }

    public async Task NotifyChatUpdated(List<Guid> memberIds, ChatDto chat)
    {
        foreach (var memberId in memberIds)
            await hubContext.Clients.Group(memberId.ToString())
                .SendAsync("ReceiveEvent", new { type = "chat_updated", chat });
    }

    public async Task NotifyChatDeleted(List<Guid> memberIds, Guid chatId)
    {
        foreach (var memberId in memberIds)
            await hubContext.Clients.Group(memberId.ToString())
                .SendAsync("ReceiveEvent", new { type = "chat_deleted", chatId });
    }

    public async Task NotifyUserOnline(List<Guid> memberIds, Guid userId, bool isOnline)
    {
        foreach (var memberId in memberIds)
            await hubContext.Clients.Group(memberId.ToString())
                .SendAsync("ReceiveEvent", new { type = "user_online", userId, isOnline });
    }

    public async Task NotifyMessageStatus(List<Guid> memberIds, Guid chatId, Guid messageId, string status)
    {
        foreach (var memberId in memberIds)
            await hubContext.Clients.Group(memberId.ToString())
                .SendAsync("ReceiveEvent", new { type = "message_status", chatId, messageId, status });
    }

    public async Task SendMentionEventAsync(Guid userId, Guid chatId, MessageDto message)
    {
        var encText    = encryption.Encrypt(userId, message.Text);
        var encMessage = message.WithEncryptedText(encText);

        await hubContext.Clients.Group(userId.ToString())
            .SendAsync("ReceiveEvent", new { type = "message_mention", chatId, message = encMessage });
    }

    public async Task SendRawEventAsync(Guid userId, object eventData)
    {
        await hubContext.Clients.Group(userId.ToString())
            .SendAsync("ReceiveEvent", eventData);
    }

    public async Task NotifyMentions(List<string> mentionedUserIds, string senderName, string chatName, Guid chatId)
    {
        foreach (var userId in mentionedUserIds)
        {
            if (!Guid.TryParse(userId, out var userGuid)) continue;
            await hubContext.Clients.Group(userGuid.ToString())
                .SendAsync("ReceiveEvent", new { type = "mention", chatId, senderName, chatName });

            // FCM push при упоминании
            await fcmService.SendAsync(userId,
                NotificationPayload.System("mention", new Dictionary<string, string>
                {
                    ["chatId"]     = chatId.ToString(),
                    ["senderName"] = senderName,
                    ["chatName"]   = chatName
                }));
        }
    }
}
