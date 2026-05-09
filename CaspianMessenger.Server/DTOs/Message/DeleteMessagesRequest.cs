namespace CaspianMessenger.Server.DTOs.Message;

public class DeleteMessagesRequest
{
    public List<Guid> Ids { get; set; } = [];
}
