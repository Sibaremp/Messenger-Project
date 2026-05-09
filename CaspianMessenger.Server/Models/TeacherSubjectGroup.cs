using System.ComponentModel.DataAnnotations;

namespace CaspianMessenger.Server.Models;

/// <summary>Назначение: преподаватель ведёт предмет в конкретной группе.</summary>
public class TeacherSubjectGroup
{
    public int Id { get; set; }
    public int SubjectId { get; set; }
    public Subject Subject { get; set; } = null!;
    public int PersonId { get; set; }
    public Person Person { get; set; } = null!;
    [MaxLength(50)] public required string GroupName { get; set; }
}
