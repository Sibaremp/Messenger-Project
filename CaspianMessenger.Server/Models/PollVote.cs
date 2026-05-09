namespace CaspianMessenger.Server.Models;

public class PollVote
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid PollId { get; set; }
    public Poll Poll { get; set; } = null!;
    public Guid OptionId { get; set; }
    public PollOption Option { get; set; } = null!;
    public Guid UserId { get; set; }
    public DateTime VotedAt { get; set; } = DateTime.UtcNow;
}
