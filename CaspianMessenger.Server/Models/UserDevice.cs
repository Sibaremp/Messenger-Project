using System.ComponentModel.DataAnnotations;

namespace CaspianMessenger.Server.Models;

public class UserDevice
{
    public int Id { get; set; }
    public Guid UserId { get; set; }

    [MaxLength(500)] public required string FcmToken { get; set; }
    [MaxLength(20)]  public string Platform { get; set; } = "android"; // android | ios | web

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public User User { get; set; } = null!;
}
