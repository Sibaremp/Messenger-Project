using System.ComponentModel.DataAnnotations;

namespace CaspianMessenger.Server.Models;

public class Chat
{
    public Guid Id { get; set; } = Guid.NewGuid();
    [MaxLength(200)] public required string Name { get; set; }
    [MaxLength(20)] public required string Type { get; set; } // direct | group | community
    public Guid? AdminId { get; set; }
    public User? Admin { get; set; }
    [MaxLength(500)] public string? AvatarPath { get; set; }
    [MaxLength(1000)] public string? Description { get; set; }
    public bool IsAcademic { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public List<Guid> PinnedMessageIds { get; set; } = [];

    public ICollection<ChatMember> Members { get; set; } = [];
    public ICollection<Message> Messages { get; set; } = [];
}
