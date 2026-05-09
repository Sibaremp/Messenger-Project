using System.ComponentModel.DataAnnotations;

namespace CaspianMessenger.Server.DTOs.Auth;

public class LoginRequest
{
    [Required] public required string Name { get; set; }
    [Required] public required string Password { get; set; }
}
