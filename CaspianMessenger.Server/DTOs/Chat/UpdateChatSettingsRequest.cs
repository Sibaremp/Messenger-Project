namespace CaspianMessenger.Server.DTOs.Chat;

public class UpdateChatSettingsRequest
{
    public string? Name { get; set; }
    public string? Description { get; set; }
    public string? AvatarPath { get; set; }
}
