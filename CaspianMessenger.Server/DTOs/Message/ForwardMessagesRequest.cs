namespace CaspianMessenger.Server.DTOs.Message;

public class ForwardMessagesRequest
{
    public List<Guid> MessageIds { get; set; } = [];
}
