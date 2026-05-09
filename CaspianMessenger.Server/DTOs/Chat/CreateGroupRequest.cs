namespace CaspianMessenger.Server.DTOs.Chat;

public class CreateGroupRequest
{
    public required string Name { get; set; }
    public required string Type { get; set; } // group | community
    public bool IsAcademic { get; set; }
    public string? Description { get; set; }
    public List<GroupMemberRequest> Members { get; set; } = [];
}

public class GroupMemberRequest
{
    public required string Name { get; set; }
    public required string Role { get; set; }
}
