using System.ComponentModel.DataAnnotations;

namespace CaspianMessenger.Server.Models;

public class Person
{
    public int Id { get; set; }

    [MaxLength(100)] public required string FirstName { get; set; }
    [MaxLength(100)] public required string LastName { get; set; }
    [MaxLength(100)] public string? MiddleName { get; set; }
    [MaxLength(20)]  public required string Role { get; set; } // student | teacher
    [MaxLength(50)]  public string? Group { get; set; }

    // Nullable link to a messenger User account
    public Guid? UserId { get; set; }
    public User? User { get; set; }
}
