namespace CaspianMessenger.Server.Models;

public class MessageReadStatus
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid MessageId { get; set; }
    public Message Message { get; set; } = null!;
    public Guid UserId { get; set; }
    public User User { get; set; } = null!;
    public DateTime ReadAt { get; set; } = DateTime.UtcNow;
}
