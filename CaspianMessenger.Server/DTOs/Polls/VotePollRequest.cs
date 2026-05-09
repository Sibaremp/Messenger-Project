namespace CaspianMessenger.Server.DTOs.Polls;

public class VotePollRequest
{
    public List<Guid> OptionIds { get; set; } = [];
}
