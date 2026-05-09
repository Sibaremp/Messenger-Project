namespace CaspianMessenger.Server.DTOs.Members;

public class AddMemberRequest
{
    public Guid UserId { get; set; }
    public string Role { get; set; } = "member";
}
