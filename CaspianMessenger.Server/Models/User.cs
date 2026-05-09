using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CaspianMessenger.Server.Models;

public class User
{
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>Auto-increment integer — used by the admin panel as the user's numeric id.</summary>
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Seq { get; set; }
    [MaxLength(100)] public required string Name { get; set; }
    [MaxLength(255)] public required string PasswordHash { get; set; }
    [MaxLength(20)] public required string Role { get; set; } // student | teacher
    [MaxLength(50)] public string? Group { get; set; }
    [MaxLength(20)] public string? Phone { get; set; }
    [MaxLength(255)] public string? Email { get; set; }
    [MaxLength(500)] public string? AvatarPath { get; set; }
    [MaxLength(500)] public string? Description { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public bool IsOnline { get; set; }
    public DateTime? LastSeen { get; set; }
    public bool MentionNotificationsOverride { get; set; } = true;

    public ICollection<ChatMember> ChatMemberships { get; set; } = [];
    public ICollection<Message> Messages { get; set; } = [];
    public ICollection<Comment> Comments { get; set; } = [];
    public ICollection<MessageReadStatus> ReadStatuses { get; set; } = [];
    public ICollection<Session> Sessions { get; set; } = [];
    public ICollection<UserDevice> Devices { get; set; } = [];
}
