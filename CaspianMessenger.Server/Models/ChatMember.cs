using System.ComponentModel.DataAnnotations;

namespace CaspianMessenger.Server.Models;

public class ChatMember
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ChatId { get; set; }
    public Chat Chat { get; set; } = null!;
    public Guid UserId { get; set; }
    public User User { get; set; } = null!;
    [MaxLength(20)] public required string Role { get; set; } // creator | admin | member
    public DateTime JoinedAt { get; set; } = DateTime.UtcNow;
}
