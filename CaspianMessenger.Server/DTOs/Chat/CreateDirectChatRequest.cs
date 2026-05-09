namespace CaspianMessenger.Server.DTOs.Chat;

public class CreateDirectChatRequest
{
    public required string ContactName { get; set; }
    public bool IsAcademic { get; set; }
}
