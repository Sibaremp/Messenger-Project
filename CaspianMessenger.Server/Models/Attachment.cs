using System.ComponentModel.DataAnnotations;

namespace CaspianMessenger.Server.Models;

public class Attachment
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid? MessageId { get; set; }
    public Message? Message { get; set; }
    public Guid? CommentId { get; set; }
    public Comment? Comment { get; set; }
    [MaxLength(500)] public required string FilePath { get; set; }
    [MaxLength(255)] public required string FileName { get; set; }
    public long FileSize { get; set; }
    [MaxLength(20)] public required string Type { get; set; } // image | video | document
    [MaxLength(100)] public required string MimeType { get; set; }
    [MaxLength(500)] public string? ThumbnailPath { get; set; }  // только для video
    public int? DurationMs { get; set; }                          // только для video
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
