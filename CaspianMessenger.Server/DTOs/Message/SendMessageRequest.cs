namespace CaspianMessenger.Server.DTOs.Message;

public class SendMessageRequest
{
    public string Text { get; set; } = string.Empty;
    /// Одиночное вложение (обратная совместимость).
    public AttachmentRequest? Attachment { get; set; }
    /// Несколько вложений — альбом фото/видео (приоритет над Attachment).
    public List<AttachmentRequest>? Attachments { get; set; }
    public ReplyRequest? ReplyTo { get; set; }
    public List<MentionRequest>? Mentions { get; set; }
}

public class MentionRequest
{
    public string UserId { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public int Offset { get; set; }
    public int Length { get; set; }
}

public class AttachmentRequest
{
    public required string Path { get; set; }
    public required string Type { get; set; }
    public required string FileName { get; set; }
    public long FileSize { get; set; }
    public string MimeType { get; set; } = string.Empty;
    public string? ThumbnailPath { get; set; }  // клиент прокидывает обратно после upload
    public int? DurationMs { get; set; }
}

public class ReplyRequest
{
    public Guid MessageId { get; set; }
    public string SenderName { get; set; } = string.Empty;
    public string Text { get; set; } = string.Empty;
}
