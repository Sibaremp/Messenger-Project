namespace CaspianMessenger.Server.DTOs.Auth;

public class AuthResponse
{
    public Guid Id { get; set; }

    /// <summary>Логин (имя аккаунта, выбранное при регистрации).</summary>
    public string Login { get; set; } = string.Empty;

    /// <summary>Алиас Login — оставлен для обратной совместимости.</summary>
    public string Name { get; set; } = string.Empty;

    public string Role { get; set; } = string.Empty;
    public string? Group { get; set; }
    public string? Phone { get; set; }
    public string? Email { get; set; }
    public string? AvatarPath { get; set; }
    public string? AvatarUrl { get; set; }
    public string? Description { get; set; }
    public string? Bio { get; set; }
    public bool IsOnline { get; set; }
    public DateTime? LastSeen { get; set; }
    public string Token { get; set; } = string.Empty;

    /// <summary>ФИО из таблицы People (null если привязки нет).</summary>
    public string? FirstName { get; set; }
    public string? LastName { get; set; }
    public string? MiddleName { get; set; }
}
