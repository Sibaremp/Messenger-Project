namespace CaspianMessenger.Server.DTOs;

public class ContactDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    /// <summary>ФИО из таблицы Person; null если участник не связан с Person.</summary>
    public string? DisplayName { get; set; }
    public string? Group { get; set; }
    public string? Phone { get; set; }
    public bool IsTeacher { get; set; }
    public string? AvatarPath { get; set; }
    public bool IsOnline { get; set; }
}
