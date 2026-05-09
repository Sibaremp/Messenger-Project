using System.ComponentModel.DataAnnotations;
namespace CaspianMessenger.Server.Models;

public class Session
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public User User { get; set; } = null!;
    [MaxLength(128)] public required string TokenHash { get; set; }
    [MaxLength(200)] public required string DeviceName { get; set; }
    [MaxLength(20)] public string? Platform { get; set; }
    [MaxLength(200)] public string? Location { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime LastActivity { get; set; } = DateTime.UtcNow;
    public bool IsActive { get; set; } = true;
}
