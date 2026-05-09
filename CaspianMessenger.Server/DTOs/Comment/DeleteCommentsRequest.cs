namespace CaspianMessenger.Server.DTOs.Comment;

public class DeleteCommentsRequest
{
    public List<Guid> Ids { get; set; } = [];
}
