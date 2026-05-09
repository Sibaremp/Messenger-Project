using System.ComponentModel.DataAnnotations;

namespace CaspianMessenger.Server.DTOs.Polls;

public class CreatePollRequest
{
    [Required] public required string Question { get; set; }
    [Required] public required List<string> Options { get; set; }
    public string Type { get; set; } = "single";
    public bool IsAnonymous { get; set; }
    public bool CanChangeVote { get; set; }
    public DateTime? Deadline { get; set; }
}
