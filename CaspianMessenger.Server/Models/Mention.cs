using System.ComponentModel.DataAnnotations;

namespace CaspianMessenger.Server.Models;

public class Mention
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid MessageId { get; set; }
    public Message Message { get; set; } = null!;
    [MaxLength(64)] public required string UserId { get; set; } // 'all' or GUID string
    [MaxLength(128)] public required string Username { get; set; }
    public int Offset { get; set; }
    public int Length { get; set; }
}
