using System.ComponentModel.DataAnnotations;

namespace CaspianMessenger.Server.Models;

public class Message
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ChatId { get; set; }
    public Chat Chat { get; set; } = null!;
    public Guid SenderId { get; set; }
    public User Sender { get; set; } = null!;
    public string Text { get; set; } = string.Empty;
    public Guid? ReplyToId { get; set; }
    public Message? ReplyTo { get; set; }
    public bool IsEdited { get; set; }
    [MaxLength(20)] public string Status { get; set; } = "sent"; // sending|sent|delivered|read
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }

    /// <summary>true — сообщение опубликовано от имени сообщества, а не конкретного пользователя.</summary>
    public bool PostAsCommunity { get; set; }

    public Guid? PollId { get; set; }
    public Poll? Poll { get; set; }

    public ICollection<Attachment> Attachments { get; set; } = [];
    public ICollection<Comment> Comments { get; set; } = [];
    public ICollection<MessageReadStatus> ReadStatuses { get; set; } = [];
    public ICollection<Mention> Mentions { get; set; } = [];
}
