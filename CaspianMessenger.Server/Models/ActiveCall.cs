namespace CaspianMessenger.Server.Models;

// In-memory call state (not persisted directly)
public class ActiveCall
{
    public Guid Id { get; set; }
    public string Type { get; set; } = "audio"; // audio | video
    public string State { get; set; } = "calling"; // calling | active | ended
    public bool IsGroup { get; set; }
    public string InitiatorId { get; set; } = string.Empty;
    public HashSet<string> Participants { get; set; } = [];
}
