using System.ComponentModel.DataAnnotations;

namespace CaspianMessenger.Server.Models;

public class Comment
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid MessageId { get; set; }
    public Message Message { get; set; } = null!;
    public Guid SenderId { get; set; }
    public User Sender { get; set; } = null!;
    public string Text { get; set; } = string.Empty;
    public Guid? ReplyToId { get; set; }
    public Comment? ReplyTo { get; set; }
    public bool IsEdited { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<Attachment> Attachments { get; set; } = [];
}
