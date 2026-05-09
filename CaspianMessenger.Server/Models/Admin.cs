using System.ComponentModel.DataAnnotations;

namespace CaspianMessenger.Server.Models;

public class Admin
{
    public int Id { get; set; }
    [MaxLength(100)] public required string Login { get; set; }
    [MaxLength(255)] public required string PasswordHash { get; set; }
}
