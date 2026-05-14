using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.DTOs.Chat;
using CaspianMessenger.Server.DTOs.Message;
using CaspianMessenger.Server.Models;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Services;

public class MessageService(AppDbContext db, ChatService chatService, NotificationService notifications, ProfanityFilter profanity)
{
    public async Task<(ChatDto? Chat, string? Error)> SendMessageAsync(Guid chatId, Guid senderId, SendMessageRequest req)
    {
        var isMember = await db.ChatMembers.AnyAsync(cm => cm.ChatId == chatId && cm.UserId == senderId);
        if (!isMember) return (null, "Not a member of this chat");

        // For community chats, only admin/creator can post messages
        var chat = await db.Chats.FindAsync(chatId);
        if (chat == null) return (null, "Chat not found");

        if (chat.Type == "community")
        {
            var member = await db.ChatMembers.FirstOrDefaultAsync(cm => cm.ChatId == chatId && cm.UserId == senderId);
            if (member?.Role == "member") return (null, "Only admins can post in community channels");
        }

        var message = new Message
        {
            ChatId = chatId,
            SenderId = senderId,
            Text = chat.IsAcademic ? profanity.Filter(req.Text) : req.Text,
            ReplyToId = req.ReplyTo?.MessageId,
            Status = "sent",
            PostAsCommunity = req.PostAsCommunity
        };

        db.Messages.Add(message);

        // Приоритет: Attachments (альбом) > Attachment (одиночное, обратная совместимость)
        List<AttachmentRequest> attachmentList;
        if (req.Attachments is { Count: > 0 })
            attachmentList = req.Attachments;
        else if (req.Attachment != null)
            attachmentList = [req.Attachment];
        else
            attachmentList = [];

        foreach (var a in attachmentList)
        {
            db.Attachments.Add(new Attachment
            {
                MessageId = message.Id,
                FilePath = a.Path,
                FileName = a.FileName,
                FileSize = a.FileSize,
                Type = a.Type,
                MimeType = a.MimeType,
                ThumbnailPath = a.ThumbnailPath,
                DurationMs = a.DurationMs
            });
        }

        var mentionedUserIds = new List<string>(); // для SignalR-уведомлений
        if (req.Mentions != null && req.Mentions.Count > 0)
        {
            var count = Math.Min(req.Mentions.Count, 10); // тихо обрезаем лишние

            var memberIds = await db.ChatMembers
                .Where(cm => cm.ChatId == chatId)
                .Select(cm => cm.UserId.ToString().ToLowerInvariant())
                .ToHashSetAsync();

            var senderMember = await db.ChatMembers
                .FirstOrDefaultAsync(cm => cm.ChatId == chatId && cm.UserId == senderId);

            foreach (var m in req.Mentions.Take(count))
            {
                if (m.UserId == "all")
                {
                    // @all — только для admin/creator; для member просто пропускаем
                    if (senderMember?.Role is "admin" or "creator")
                        mentionedUserIds.Add("all");
                }
                else
                {
                    // Нормализуем UUID и проверяем членство; невалидные — пропускаем
                    var normalized = m.UserId.ToLowerInvariant();
                    if (!memberIds.Contains(normalized)) continue;
                    mentionedUserIds.Add(normalized);
                }

                db.Mentions.Add(new Mention
                {
                    MessageId = message.Id,
                    UserId = m.UserId,
                    Username = m.Username,
                    Offset = m.Offset,
                    Length = m.Length
                });
            }
        }

        await db.SaveChangesAsync();

        var chatDto = await chatService.GetChatAsync(chatId, senderId);

        // SignalR: уведомить упомянутых пользователей
        if (mentionedUserIds.Count > 0 && chatDto != null)
        {
            var sentMessage = chatDto.Messages.LastOrDefault();
            if (sentMessage != null)
            {
                if (mentionedUserIds.Contains("all"))
                {
                    // @all → всем участникам чата
                    var allMemberIds = await chatService.GetChatMemberIdsAsync(chatId);
                    foreach (var memberId in allMemberIds.Where(id => id != senderId))
                        await notifications.SendMentionEventAsync(memberId, chatId, sentMessage);
                }
                else
                {
                    foreach (var uidStr in mentionedUserIds)
                    {
                        if (Guid.TryParse(uidStr, out var mentionedGuid) && mentionedGuid != senderId)
                            await notifications.SendMentionEventAsync(mentionedGuid, chatId, sentMessage);
                    }
                }
            }
        }

        // SignalR: уведомить автора оригинального сообщения о том, что ему ответили
        if (req.ReplyTo?.MessageId != null && chatDto != null)
        {
            var originalMessage = await db.Messages.FindAsync(req.ReplyTo.MessageId);
            if (originalMessage != null && originalMessage.SenderId != senderId)
            {
                var sentMessage = chatDto.Messages.LastOrDefault();
                if (sentMessage != null)
                {
                    await notifications.SendRawEventAsync(originalMessage.SenderId, new
                    {
                        type = "message_reply",
                        chatId,
                        message = sentMessage
                    });
                }
            }
        }

        return (chatDto, null);
    }

    public async Task<(ChatDto? Chat, string? Error)> EditMessageAsync(Guid chatId, Guid messageId, Guid userId, EditMessageRequest req)
    {
        var message = await db.Messages.FirstOrDefaultAsync(m => m.Id == messageId && m.ChatId == chatId);
        if (message == null) return (null, "Message not found");
        if (message.SenderId != userId) return (null, "Can only edit own messages");

        var editChat = await db.Chats.FindAsync(chatId);
        message.Text = (editChat?.IsAcademic == true) ? profanity.Filter(req.Text) : req.Text;
        message.IsEdited = true;
        message.UpdatedAt = DateTime.UtcNow;

        await db.SaveChangesAsync();
        return (await chatService.GetChatAsync(chatId, userId), null);
    }

    public async Task<(ChatDto? Chat, string? Error)> DeleteMessagesAsync(Guid chatId, Guid userId, List<Guid> messageIds)
    {
        var member = await db.ChatMembers.FirstOrDefaultAsync(cm => cm.ChatId == chatId && cm.UserId == userId);
        if (member == null) return (null, "Not a member");

        var isAdminOrCreator = member.Role is "admin" or "creator";

        var messages = await db.Messages
            .Where(m => m.ChatId == chatId && messageIds.Contains(m.Id))
            .ToListAsync();

        foreach (var message in messages)
        {
            if (message.SenderId != userId && !isAdminOrCreator)
                return (null, "Forbidden: can only delete own messages or must be admin/creator");
            db.Messages.Remove(message);
        }

        await db.SaveChangesAsync();
        return (await chatService.GetChatAsync(chatId, userId), null);
    }

    public async Task<(ChatDto? Chat, string? Error)> ForwardMessagesAsync(Guid targetChatId, Guid userId, List<Guid> messageIds)
    {
        var isMember = await db.ChatMembers.AnyAsync(cm => cm.ChatId == targetChatId && cm.UserId == userId);
        if (!isMember) return (null, "Not a member of target chat");

        var messages = await db.Messages
            .Where(m => messageIds.Contains(m.Id))
            .Include(m => m.Attachments)
            .ToListAsync();

        foreach (var original in messages)
        {
            var forwarded = new Message
            {
                ChatId = targetChatId,
                SenderId = userId,
                Text = original.Text,
                Status = "sent"
            };
            db.Messages.Add(forwarded);

            foreach (var att in original.Attachments)
            {
                db.Attachments.Add(new Attachment
                {
                    MessageId = forwarded.Id,
                    FilePath = att.FilePath,
                    FileName = att.FileName,
                    FileSize = att.FileSize,
                    Type = att.Type,
                    MimeType = att.MimeType
                });
            }
        }

        await db.SaveChangesAsync();
        return (await chatService.GetChatAsync(targetChatId, userId), null);
    }

    public async Task<List<object>> SearchMessagesAsync(Guid userId, string query)
    {
        var chatIds = await db.ChatMembers
            .Where(cm => cm.UserId == userId)
            .Select(cm => cm.ChatId)
            .ToListAsync();

        var messages = await db.Messages
            .Where(m => chatIds.Contains(m.ChatId) && m.Text.Contains(query))
            .Include(m => m.Sender)
            .Include(m => m.Chat)
            .Take(50)
            .ToListAsync();

        return messages.Select(m => (object)new
        {
            chat = new { m.Chat.Id, m.Chat.Name, m.Chat.Type },
            message = ChatService.MapMessageToDto(m)
        }).ToList();
    }

    public async Task<(ChatDto? Chat, string? Error)> PinMessageAsync(Guid chatId, Guid messageId, Guid userId)
    {
        var chat = await db.Chats.FindAsync(chatId);
        if (chat == null) return (null, "Chat not found");

        var member = await db.ChatMembers.FirstOrDefaultAsync(cm => cm.ChatId == chatId && cm.UserId == userId);
        if (member == null) return (null, "Not a member");

        // Direct chats: any member; group/community: admin or creator
        if (chat.Type != "direct" && member.Role == "member")
            return (null, "Only admin or creator can pin messages in group chats");

        var messageExists = await db.Messages.AnyAsync(m => m.Id == messageId && m.ChatId == chatId);
        if (!messageExists) return (null, "Message not found");

        if (chat.PinnedMessageIds.Contains(messageId))
            return (null, "Message is already pinned");

        if (chat.PinnedMessageIds.Count >= 5)
            return (null, "Cannot pin more than 5 messages");

        chat.PinnedMessageIds.Add(messageId);
        await db.SaveChangesAsync();
        return (await chatService.GetChatAsync(chatId, userId), null);
    }

    public async Task<(ChatDto? Chat, string? Error)> UnpinMessageAsync(Guid chatId, Guid messageId, Guid userId)
    {
        var chat = await db.Chats.FindAsync(chatId);
        if (chat == null) return (null, "Chat not found");

        var member = await db.ChatMembers.FirstOrDefaultAsync(cm => cm.ChatId == chatId && cm.UserId == userId);
        if (member == null) return (null, "Not a member");

        // Direct chats: any member; group/community: admin or creator
        if (chat.Type != "direct" && member.Role == "member")
            return (null, "Only admin or creator can unpin messages in group chats");

        if (!chat.PinnedMessageIds.Contains(messageId))
            return (null, "Message is not pinned");

        chat.PinnedMessageIds.Remove(messageId);
        await db.SaveChangesAsync();
        return (await chatService.GetChatAsync(chatId, userId), null);
    }

    /// <summary>
    /// Marks ALL unread messages in a chat as read for the given user.
    /// Called when the user opens a chat (POST /chats/{id}/read).
    /// </summary>
    public async Task<string?> MarkAllMessagesReadAsync(Guid chatId, Guid userId)
    {
        var isMember = await db.ChatMembers.AnyAsync(cm => cm.ChatId == chatId && cm.UserId == userId);
        if (!isMember) return "Not a member";

        var unreadMessages = await db.Messages
            .Where(m => m.ChatId == chatId && m.SenderId != userId)
            .Where(m => !db.MessageReadStatuses.Any(r => r.MessageId == m.Id && r.UserId == userId))
            .ToListAsync();

        if (unreadMessages.Count == 0) return null;

        var notifyMap = new Dictionary<Guid, List<Guid>>(); // senderId → messageIds

        foreach (var message in unreadMessages)
        {
            db.MessageReadStatuses.Add(new MessageReadStatus { MessageId = message.Id, UserId = userId });
            message.Status = "read";

            if (!notifyMap.TryGetValue(message.SenderId, out var list))
            {
                list = [];
                notifyMap[message.SenderId] = list;
            }
            list.Add(message.Id);
        }

        await db.SaveChangesAsync();

        // Notify each sender that their messages were read
        foreach (var (senderId, msgIds) in notifyMap)
        {
            foreach (var msgId in msgIds)
            {
                await notifications.NotifyMessageStatus(
                    [senderId], chatId, msgId, "read");
            }
        }

        return null;
    }

    /// <summary>
    /// Переводит статус сообщений sent → delivered и уведомляет отправителей.
    /// Вызывается сервером SignalR (MarkDelivered) когда клиент получил сообщение.
    /// Не понижает статус — read остаётся read.
    /// </summary>
    public async Task MarkMessagesDeliveredAsync(Guid recipientId, Guid chatId, List<Guid> messageIds)
    {
        if (messageIds.Count == 0) return;

        var notifyMap = new Dictionary<Guid, List<Guid>>(); // senderId → [messageId]

        foreach (var messageId in messageIds)
        {
            var message = await db.Messages.FindAsync(messageId);
            if (message == null) continue;
            if (message.SenderId == recipientId) continue; // не обновляем собственные
            if (message.Status is "delivered" or "read") continue; // не понижаем

            message.Status = "delivered";

            if (!notifyMap.TryGetValue(message.SenderId, out var list))
            {
                list = [];
                notifyMap[message.SenderId] = list;
            }
            list.Add(messageId);
        }

        if (notifyMap.Count == 0) return;

        await db.SaveChangesAsync();

        foreach (var (senderId, msgIds) in notifyMap)
            foreach (var msgId in msgIds)
                await notifications.NotifyMessageStatus([senderId], chatId, msgId, "delivered");
    }

    public async Task MarkMessagesReadAsync(Guid userId, Guid chatId, List<Guid> messageIds)
    {
        // Собираем сообщения, статус которых реально изменился на "read", чтобы
        // потом уведомить их отправителей по SignalR. Без уведомления у
        // отправителя навсегда останутся серые ✓✓ и он не увидит «прочитано».
        var notifyList = new List<(Guid messageId, Guid senderId)>();

        foreach (var messageId in messageIds)
        {
            var alreadyRead = await db.MessageReadStatuses
                .AnyAsync(r => r.MessageId == messageId && r.UserId == userId);
            if (alreadyRead) continue;

            db.MessageReadStatuses.Add(new MessageReadStatus
            {
                MessageId = messageId,
                UserId = userId
            });

            var message = await db.Messages.FindAsync(messageId);
            if (message != null && message.SenderId != userId)
            {
                message.Status = "read";
                notifyList.Add((messageId, message.SenderId));
            }
        }

        await db.SaveChangesAsync();

        // Рассылаем новое состояние отправителю по одному событию на сообщение.
        foreach (var (msgId, senderId) in notifyList)
        {
            await notifications.NotifyMessageStatus(
                new List<Guid> { senderId }, chatId, msgId, "read");
        }
    }
}
