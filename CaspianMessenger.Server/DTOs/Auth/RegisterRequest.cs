using System.ComponentModel.DataAnnotations;

namespace CaspianMessenger.Server.DTOs.Auth;

public class RegisterRequest
{
    /// <summary>ID из таблицы People — обязателен. Role и Group берутся из него.</summary>
    [Required] public int PersonId { get; set; }

    /// <summary>Логин (имя в мессенджере), придумывает пользователь.</summary>
    [Required] public required string Name { get; set; }

    [Required] public required string Password { get; set; }

    public string? Phone { get; set; }

    [EmailAddress] public string? Email { get; set; }
}
