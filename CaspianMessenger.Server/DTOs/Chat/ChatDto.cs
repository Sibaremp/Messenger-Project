namespace CaspianMessenger.Server.DTOs.Chat;

public class MentionDto
{
    public string UserId { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public int Offset { get; set; }
    public int Length { get; set; }
}

public class PollDto
{
    public Guid Id { get; set; }
    public string Question { get; set; } = string.Empty;
    public List<PollOptionDto> Options { get; set; } = [];
    public string Type { get; set; } = "single";
    public bool IsAnonymous { get; set; }
    public bool CanChangeVote { get; set; }
    public DateTime? Deadline { get; set; }
    public bool IsClosed { get; set; }
    public List<Guid> MyVotes { get; set; } = [];
    public Dictionary<string, List<Guid>> UserVotes { get; set; } = [];
}

public class PollOptionDto
{
    public Guid Id { get; set; }
    public string Text { get; set; } = string.Empty;
    public int Votes { get; set; }
}

public class ChatDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public Guid? AdminId { get; set; }
    public string? AdminName { get; set; }
    public string? AvatarPath { get; set; }
    public string? Description { get; set; }
    public bool IsAcademic { get; set; }
    public DateTime CreatedAt { get; set; }
    public int UnreadCount { get; set; }
    public List<Guid> PinnedMessageIds { get; set; } = [];
    public List<MemberDto> Members { get; set; } = [];
    public List<MessageDto> Messages { get; set; } = [];
}

public class MemberDto
{
    public Guid UserId { get; set; }
    public Guid Id => UserId; // алиас для клиентов, читающих "id"
    public string Name { get; set; } = string.Empty;
    /// <summary>ФИО из таблицы Person; null если участник не связан с Person.</summary>
    public string? DisplayName { get; set; }
    public string? Group { get; set; }
    public string? AvatarPath { get; set; }
    public string Role { get; set; } = string.Empty;
    public bool IsOnline { get; set; }
}

public class MessageDto
{
    public Guid Id { get; set; }
    public Guid ChatId { get; set; }
    public Guid SenderId { get; set; }
    public string SenderName { get; set; } = string.Empty;
    /// <summary>ФИО в формате «Фамилия И.О.» из таблицы Person; null если не связан с Person.</summary>
    public string? SenderDisplayName { get; set; }
    public string? SenderGroup { get; set; }
    public string? SenderAvatarPath { get; set; }
    /// <summary>true — сообщение опубликовано от имени сообщества (скрыть автора).</summary>
    public bool PostAsCommunity { get; set; }
    public string Text { get; set; } = string.Empty;
    public Guid? ReplyToId { get; set; }
    public ReplyDto? ReplyTo { get; set; }
    public bool IsEdited { get; set; }
    public string Status { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public DateTime Time { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public AttachmentDto? Attachment { get; set; }
    public List<AttachmentDto> Attachments { get; set; } = [];
    public List<CommentDto> Comments { get; set; } = [];
    public List<MentionDto> Mentions { get; set; } = [];
    public PollDto? Poll { get; set; }

    /// <summary>
    /// Returns a shallow copy of this MessageDto with <see cref="Text"/> replaced by
    /// <paramref name="encryptedText"/>. Used by NotificationService to send per-recipient
    /// encrypted SignalR events without mutating the original DTO.
    /// </summary>
    public MessageDto WithEncryptedText(string encryptedText) => new()
    {
        Id                = Id,
        ChatId            = ChatId,
        SenderId          = SenderId,
        SenderName        = SenderName,
        SenderDisplayName = SenderDisplayName,
        SenderGroup       = SenderGroup,
        SenderAvatarPath  = SenderAvatarPath,
        PostAsCommunity   = PostAsCommunity,
        Text              = encryptedText,
        ReplyToId        = ReplyToId,
        ReplyTo          = ReplyTo,
        IsEdited         = IsEdited,
        Status           = Status,
        CreatedAt        = CreatedAt,
        Time             = Time,
        UpdatedAt        = UpdatedAt,
        Attachment       = Attachment,
        Attachments      = Attachments,
        Comments         = Comments,
        Mentions         = Mentions,
        Poll             = Poll
    };
}

public class ReplyDto
{
    public Guid MessageId { get; set; }
    public string SenderName { get; set; } = string.Empty;
    public string Text { get; set; } = string.Empty;
}

public class AttachmentDto
{
    public Guid Id { get; set; }
    public string Path { get; set; } = string.Empty;
    public string FileName { get; set; } = string.Empty;
    public long FileSize { get; set; }
    public string Type { get; set; } = string.Empty;
    public string MimeType { get; set; } = string.Empty;
    public string? ThumbnailPath { get; set; }  // только для video
    public int? DurationMs { get; set; }          // только для video
}

public class CommentDto
{
    public Guid Id { get; set; }
    public Guid MessageId { get; set; }
    public Guid SenderId { get; set; }
    public string SenderName { get; set; } = string.Empty;
    /// <summary>ФИО в формате «Фамилия И.О.» из таблицы Person; null если не связан с Person.</summary>
    public string? SenderDisplayName { get; set; }
    public string? SenderGroup { get; set; }
    public string? SenderAvatarPath { get; set; }
    public string Text { get; set; } = string.Empty;
    public Guid? ReplyToId { get; set; }
    public bool IsEdited { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime Time { get; set; }
    public AttachmentDto? Attachment { get; set; }
    public List<AttachmentDto> Attachments { get; set; } = [];
}
