using System.ComponentModel.DataAnnotations;

namespace CaspianMessenger.Server.Models;

public class Poll
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Question { get; set; } = string.Empty;
    [MaxLength(16)] public string Type { get; set; } = "single"; // single | multiple
    public bool IsAnonymous { get; set; }
    public bool CanChangeVote { get; set; }
    public DateTime? Deadline { get; set; }
    public bool IsClosed { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public ICollection<PollOption> Options { get; set; } = [];
    public ICollection<PollVote> Votes { get; set; } = [];
}
