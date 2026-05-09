using System.ComponentModel.DataAnnotations;

namespace CaspianMessenger.Server.Models;

public class Notification
{
    public int Id { get; set; }
    [MaxLength(200)] public required string Title { get; set; }
    [MaxLength(2000)] public required string Body { get; set; }
    [MaxLength(20)] public required string Target { get; set; } // all | students | teachers
    public DateTime SentAt { get; set; } = DateTime.UtcNow;
    public int SentCount { get; set; }
}
