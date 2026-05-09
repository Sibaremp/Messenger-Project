namespace CaspianMessenger.Server.Models;

public class Call
{
    public Guid Id { get; set; }
    public string Type { get; set; } = "audio"; // audio | video
    public string State { get; set; } = "calling"; // calling | active | ended
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<CallParticipant> Participants { get; set; } = [];
}
