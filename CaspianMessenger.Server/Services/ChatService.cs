using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.DTOs.Chat;
using CaspianMessenger.Server.Models;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Services;

public class ChatService(AppDbContext db)
{
    public async Task<List<ChatDto>> GetUserChatsAsync(Guid userId)
    {
        var chatIds = await db.ChatMembers
            .Where(cm => cm.UserId == userId)
            .Select(cm => cm.ChatId)
            .ToListAsync();

        var chats = await db.Chats
            .Where(c => chatIds.Contains(c.Id))
            .Include(c => c.Members).ThenInclude(m => m.User)
            .Include(c => c.Messages.OrderByDescending(m => m.CreatedAt).Take(20))
                .ThenInclude(m => m.Sender)
            .Include(c => c.Messages).ThenInclude(m => m.Attachments)
            .Include(c => c.Messages).ThenInclude(m => m.Comments).ThenInclude(cm => cm.Sender)
            .Include(c => c.Messages).ThenInclude(m => m.Comments).ThenInclude(cm => cm.Attachments)
            .Include(c => c.Messages).ThenInclude(m => m.Poll).ThenInclude(p => p!.Options)
            .Include(c => c.Messages).ThenInclude(m => m.Poll).ThenInclude(p => p!.Votes)
            .Include(c => c.Messages).ThenInclude(m => m.Mentions)
            .ToListAsync();

        // Unread count: messages sent by others that the current user hasn't read yet
        var unreadCounts = await db.Messages
            .Where(m => chatIds.Contains(m.ChatId) && m.SenderId != userId)
            .Where(m => !db.MessageReadStatuses.Any(r => r.MessageId == m.Id && r.UserId == userId))
            .GroupBy(m => m.ChatId)
            .Select(g => new { ChatId = g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.ChatId, x => x.Count);

        return chats.Select(c => MapChatToDto(c, userId, unreadCounts.GetValueOrDefault(c.Id))).ToList();
    }

    public async Task<ChatDto?> GetChatAsync(Guid chatId, Guid userId, int offset = 0, int limit = 50)
    {
        var isMember = await db.ChatMembers.AnyAsync(cm => cm.ChatId == chatId && cm.UserId == userId);
        if (!isMember) return null;

        var chat = await db.Chats
            .Where(c => c.Id == chatId)
            .Include(c => c.Members).ThenInclude(m => m.User)
            .FirstOrDefaultAsync();

        if (chat == null) return null;

        var messages = await db.Messages
            .Where(m => m.ChatId == chatId)
            .OrderByDescending(m => m.CreatedAt)
            .Skip(offset)
            .Take(limit)
            .Include(m => m.Sender)
            .Include(m => m.Attachments)
            .Include(m => m.ReplyTo).ThenInclude(r => r!.Sender)
            .Include(m => m.Comments).ThenInclude(c => c.Sender)
            .Include(m => m.Comments).ThenInclude(c => c.Attachments)
            .Include(m => m.Poll).ThenInclude(p => p!.Options)
            .Include(m => m.Poll).ThenInclude(p => p!.Votes)
            .Include(m => m.Mentions)
            .ToListAsync();

        messages.Reverse();
        chat.Messages = messages;

        return MapChatToDto(chat, userId);
    }

    public async Task<(ChatDto? Chat, string? Error)> CreateDirectChatAsync(Guid currentUserId, CreateDirectChatRequest req)
    {
        var contact = await db.Users.FirstOrDefaultAsync(u => u.Name == req.ContactName);
        if (contact == null) return (null, "Contact not found");

        // Check if direct chat already exists
        var existingChatId = await db.ChatMembers
            .Where(cm => cm.UserId == currentUserId)
            .Select(cm => cm.ChatId)
            .Intersect(
                db.ChatMembers.Where(cm => cm.UserId == contact.Id).Select(cm => cm.ChatId)
            )
            .Join(db.Chats.Where(c => c.Type == "direct"), id => id, c => c.Id, (id, c) => id)
            .FirstOrDefaultAsync();

        if (existingChatId != Guid.Empty)
        {
            var existing = await GetChatAsync(existingChatId, currentUserId);
            return (existing, null);
        }

        var chat = new Chat
        {
            Name = contact.Name,
            Type = "direct",
            IsAcademic = req.IsAcademic
        };

        db.Chats.Add(chat);
        db.ChatMembers.Add(new ChatMember { ChatId = chat.Id, UserId = currentUserId, Role = "member" });
        db.ChatMembers.Add(new ChatMember { ChatId = chat.Id, UserId = contact.Id, Role = "member" });
        await db.SaveChangesAsync();

        return (await GetChatAsync(chat.Id, currentUserId), null);
    }

    public async Task<(ChatDto? Chat, string? Error)> CreateGroupChatAsync(Guid currentUserId, CreateGroupRequest req)
    {
        if (req.Type != "group" && req.Type != "community")
            return (null, "Invalid type");

        // Академические чаты может создавать только преподаватель
        if (req.IsAcademic)
        {
            var creator = await db.Users.FindAsync(currentUserId);
            if (creator == null || creator.Role != "teacher")
                return (null, "Только преподаватель может создавать академические группы");
        }

        var chat = new Chat
        {
            Name = req.Name,
            Type = req.Type,
            IsAcademic = req.IsAcademic,
            Description = req.Description,
            AdminId = currentUserId
        };

        db.Chats.Add(chat);
        db.ChatMembers.Add(new ChatMember { ChatId = chat.Id, UserId = currentUserId, Role = "creator" });

        foreach (var memberReq in req.Members)
        {
            var user = await db.Users.FirstOrDefaultAsync(u => u.Name == memberReq.Name);
            if (user == null || user.Id == currentUserId) continue;
            db.ChatMembers.Add(new ChatMember { ChatId = chat.Id, UserId = user.Id, Role = memberReq.Role });
        }

        await db.SaveChangesAsync();
        return (await GetChatAsync(chat.Id, currentUserId), null);
    }

    public async Task<(ChatDto? Chat, string? Error)> UpdateChatSettingsAsync(Guid chatId, Guid userId, UpdateChatSettingsRequest req)
    {
        var member = await db.ChatMembers.FirstOrDefaultAsync(cm => cm.ChatId == chatId && cm.UserId == userId);
        if (member == null || (member.Role != "creator" && member.Role != "admin"))
            return (null, "Forbidden");

        var chat = await db.Chats.FindAsync(chatId);
        if (chat == null) return (null, "Chat not found");

        if (req.Name != null) chat.Name = req.Name;
        if (req.Description != null) chat.Description = req.Description;
        if (req.AvatarPath != null) chat.AvatarPath = req.AvatarPath;

        await db.SaveChangesAsync();
        return (await GetChatAsync(chatId, userId), null);
    }

    public async Task<(bool Success, string? Error)> DeleteChatAsync(Guid chatId, Guid userId)
    {
        var member = await db.ChatMembers.FirstOrDefaultAsync(cm => cm.ChatId == chatId && cm.UserId == userId);
        if (member == null || member.Role != "creator")
            return (false, "Only creator can delete the chat");

        var chat = await db.Chats.FindAsync(chatId);
        if (chat == null) return (false, "Chat not found");

        db.Chats.Remove(chat);
        await db.SaveChangesAsync();
        return (true, null);
    }

    public async Task<(ChatDto? Chat, string? Error)> AddMemberAsync(Guid chatId, Guid requesterId, Guid userId, string role)
    {
        var requester = await db.ChatMembers.FirstOrDefaultAsync(cm => cm.ChatId == chatId && cm.UserId == requesterId);
        if (requester == null || (requester.Role != "creator" && requester.Role != "admin"))
            return (null, "Forbidden");

        var existing = await db.ChatMembers.AnyAsync(cm => cm.ChatId == chatId && cm.UserId == userId);
        if (existing) return (null, "User already in chat");

        db.ChatMembers.Add(new ChatMember { ChatId = chatId, UserId = userId, Role = role });
        await db.SaveChangesAsync();
        return (await GetChatAsync(chatId, requesterId), null);
    }

    public async Task<(ChatDto? Chat, string? Error)> UpdateMemberRoleAsync(Guid chatId, Guid requesterId, Guid targetUserId, string newRole)
    {
        var requester = await db.ChatMembers.FirstOrDefaultAsync(cm => cm.ChatId == chatId && cm.UserId == requesterId);
        if (requester == null || requester.Role != "creator")
            return (null, "Only creator can change roles");

        var target = await db.ChatMembers.FirstOrDefaultAsync(cm => cm.ChatId == chatId && cm.UserId == targetUserId);
        if (target == null) return (null, "Member not found");

        target.Role = newRole;
        await db.SaveChangesAsync();
        return (await GetChatAsync(chatId, requesterId), null);
    }

    public async Task<(ChatDto? Chat, string? Error)> RemoveMemberAsync(Guid chatId, Guid requesterId, Guid targetUserId)
    {
        var requester = await db.ChatMembers.FirstOrDefaultAsync(cm => cm.ChatId == chatId && cm.UserId == requesterId);
        if (requester == null || (requester.Role != "creator" && requester.Role != "admin"))
            return (null, "Forbidden");

        var target = await db.ChatMembers.FirstOrDefaultAsync(cm => cm.ChatId == chatId && cm.UserId == targetUserId);
        if (target == null) return (null, "Member not found");

        db.ChatMembers.Remove(target);
        await db.SaveChangesAsync();
        return (await GetChatAsync(chatId, requesterId), null);
    }

    public async Task<List<ChatDto>> SearchChatsAsync(Guid userId, string query)
    {
        var chatIds = await db.ChatMembers
            .Where(cm => cm.UserId == userId)
            .Select(cm => cm.ChatId)
            .ToListAsync();

        var chats = await db.Chats
            .Where(c => chatIds.Contains(c.Id) &&
                        (c.Name.Contains(query) || (c.Description != null && c.Description.Contains(query))))
            .Include(c => c.Members).ThenInclude(m => m.User)
            .Include(c => c.Messages.OrderByDescending(m => m.CreatedAt).Take(5)).ThenInclude(m => m.Sender)
            .ToListAsync();

        return chats.Select(c => MapChatToDto(c, userId)).ToList();
    }

    public async Task<List<Guid>> GetChatMemberIdsAsync(Guid chatId)
    {
        return await db.ChatMembers
            .Where(cm => cm.ChatId == chatId)
            .Select(cm => cm.UserId)
            .ToListAsync();
    }

    public static ChatDto MapChatToDto(Chat chat, Guid? requestingUserId = null, int unreadCount = 0)
    {
        // Для личных чатов отдаём имя и аватар "собеседника" относительно
        // запрашивающего пользователя, а не того, кто создавал чат.
        string displayName = chat.Name;
        string? displayAvatar = chat.AvatarPath;
        string? displayDescription = chat.Description;

        if (chat.Type == "direct" && requestingUserId.HasValue)
        {
            var peer = chat.Members
                .FirstOrDefault(m => m.UserId != requestingUserId.Value)?.User;
            if (peer != null)
            {
                displayName = peer.Name;
                displayAvatar = peer.AvatarPath;
                displayDescription = peer.Description;
            }
        }

        return new ChatDto
        {
            Id = chat.Id,
            Name = displayName,
            Type = chat.Type,
            AdminId = chat.AdminId,
            AdminName = chat.Members.FirstOrDefault(m => m.UserId == chat.AdminId)?.User?.Name,
            AvatarPath = displayAvatar,
            Description = displayDescription,
            IsAcademic = chat.IsAcademic,
            CreatedAt = chat.CreatedAt,
            UnreadCount = unreadCount,
            Members = chat.Members.Select(m => new MemberDto
            {
                UserId = m.UserId,
                Name = m.User?.Name ?? "",
                Group = m.User?.Group,
                AvatarPath = m.User?.AvatarPath,
                Role = m.Role,
                IsOnline = m.User?.IsOnline ?? false
            }).ToList(),
            PinnedMessageIds = chat.PinnedMessageIds,
            Messages = chat.Messages.Select(m => MapMessageToDto(m, requestingUserId ?? default)).ToList()
        };
    }

    public static MessageDto MapMessageToDto(Message msg, Guid currentUserId = default) => new()
    {
        Id = msg.Id,
        ChatId = msg.ChatId,
        SenderId = msg.SenderId,
        SenderName = msg.Sender?.Name ?? "",
        SenderGroup = msg.Sender?.Group,
        SenderAvatarPath = msg.Sender?.AvatarPath,
        Text = msg.Text,
        ReplyToId = msg.ReplyToId,
        ReplyTo = msg.ReplyTo != null ? new ReplyDto
        {
            MessageId = msg.ReplyTo.Id,
            SenderName = msg.ReplyTo.Sender?.Name ?? "",
            Text = msg.ReplyTo.Text
        } : null,
        IsEdited = msg.IsEdited,
        Status = msg.Status,
        CreatedAt = msg.CreatedAt,
        Time = msg.CreatedAt,
        UpdatedAt = msg.UpdatedAt,
        Attachment = msg.Attachments.Select(a => new AttachmentDto
        {
            Id = a.Id,
            Path = a.FilePath,
            FileName = a.FileName,
            FileSize = a.FileSize,
            Type = a.Type,
            MimeType = a.MimeType,
            ThumbnailPath = a.ThumbnailPath,
            DurationMs = a.DurationMs
        }).FirstOrDefault(),
        Attachments = msg.Attachments.Select(a => new AttachmentDto
        {
            Id = a.Id,
            Path = a.FilePath,
            FileName = a.FileName,
            FileSize = a.FileSize,
            Type = a.Type,
            MimeType = a.MimeType,
            ThumbnailPath = a.ThumbnailPath,
            DurationMs = a.DurationMs
        }).ToList(),
        Comments = msg.Comments.Select(c => new CommentDto
        {
            Id = c.Id,
            MessageId = c.MessageId,
            SenderId = c.SenderId,
            SenderName = c.Sender?.Name ?? "",
            SenderGroup = c.Sender?.Group,
            SenderAvatarPath = c.Sender?.AvatarPath,
            Text = c.Text,
            ReplyToId = c.ReplyToId,
            IsEdited = c.IsEdited,
            CreatedAt = c.CreatedAt,
            Time = c.CreatedAt,
            Attachment = c.Attachments.Select(a => new AttachmentDto
            {
                Id = a.Id,
                Path = a.FilePath,
                FileName = a.FileName,
                FileSize = a.FileSize,
                Type = a.Type,
                MimeType = a.MimeType
            }).FirstOrDefault(),
            Attachments = c.Attachments.Select(a => new AttachmentDto
            {
                Id = a.Id,
                Path = a.FilePath,
                FileName = a.FileName,
                FileSize = a.FileSize,
                Type = a.Type,
                MimeType = a.MimeType
            }).ToList()
        }).ToList(),
        Mentions = msg.Mentions.Select(m => new MentionDto
        {
            UserId = m.UserId,
            Username = m.Username,
            Offset = m.Offset,
            Length = m.Length
        }).ToList(),
        Poll = msg.Poll != null ? PollService.MapPollToDto(msg.Poll, currentUserId) : null
    };
}
