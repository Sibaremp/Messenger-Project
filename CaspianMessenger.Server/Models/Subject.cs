using System.ComponentModel.DataAnnotations;

namespace CaspianMessenger.Server.Models;

public class Subject
{
    public int Id { get; set; }
    [MaxLength(200)] public required string Name { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<TeacherSubjectGroup> Assignments { get; set; } = [];
}
