namespace CaspianMessenger.Server.Models;

public class CallParticipant
{
    public int Id { get; set; }
    public Guid CallId { get; set; }
    public string UserId { get; set; } = string.Empty;

    public Call Call { get; set; } = null!;
}
