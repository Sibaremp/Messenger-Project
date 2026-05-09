namespace CaspianMessenger.Server.DTOs;

public class ContactDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Group { get; set; }
    public string? Phone { get; set; }
    public bool IsTeacher { get; set; }
    public string? AvatarPath { get; set; }
    public bool IsOnline { get; set; }
}
