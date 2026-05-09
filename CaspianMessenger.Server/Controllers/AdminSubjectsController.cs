using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/admin")]
[Authorize(Policy = "AdminOnly")]
public class AdminSubjectsController(
    AppDbContext db,
    ILogger<AdminSubjectsController> logger) : ControllerBase
{
    // ── SUBJECTS ──────────────────────────────────────────────────────────────

    /// GET /api/admin/subjects
    [HttpGet("subjects")]
    public async Task<IActionResult> GetSubjects()
    {
        var subjects = await db.Subjects
            .OrderBy(s => s.Name)
            .Select(s => new
            {
                id              = s.Id,
                name            = s.Name,
                createdAt       = s.CreatedAt,
                assignmentCount = s.Assignments.Count
            })
            .ToListAsync();

        return Ok(subjects);
    }

    /// POST /api/admin/subjects
    [HttpPost("subjects")]
    public async Task<IActionResult> CreateSubject([FromBody] CreateSubjectRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Name))
            return BadRequest(new { message = "Название предмета не может быть пустым" });

        var name = req.Name.Trim();
        if (await db.Subjects.AnyAsync(s => s.Name == name))
            return Conflict(new { message = "Предмет с таким названием уже существует" });

        var subject = new Subject { Name = name };
        db.Subjects.Add(subject);
        await db.SaveChangesAsync();

        logger.LogInformation("Admin created subject '{Name}' (Id={Id})", subject.Name, subject.Id);
        return Ok(new { id = subject.Id, name = subject.Name, createdAt = subject.CreatedAt, assignmentCount = 0 });
    }

    /// PUT /api/admin/subjects/{id}
    [HttpPut("subjects/{id:int}")]
    public async Task<IActionResult> UpdateSubject(int id, [FromBody] CreateSubjectRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Name))
            return BadRequest(new { message = "Название предмета не может быть пустым" });

        var subject = await db.Subjects.FindAsync(id);
        if (subject == null) return NotFound(new { message = "Предмет не найден" });

        var name = req.Name.Trim();
        if (await db.Subjects.AnyAsync(s => s.Name == name && s.Id != id))
            return Conflict(new { message = "Предмет с таким названием уже существует" });

        subject.Name = name;
        await db.SaveChangesAsync();

        logger.LogInformation("Admin renamed subject Id={Id} to '{Name}'", id, name);
        return Ok(new { id = subject.Id, name = subject.Name });
    }

    /// DELETE /api/admin/subjects/{id}
    [HttpDelete("subjects/{id:int}")]
    public async Task<IActionResult> DeleteSubject(int id)
    {
        var subject = await db.Subjects.FindAsync(id);
        if (subject == null) return NotFound(new { message = "Предмет не найден" });

        // Все чаты этого предмета (по всем группам) — удаляем каскадом
        var chatNames = await db.TeacherSubjectGroups
            .Where(t => t.SubjectId == id)
            .Select(t => $"{subject.Name} {t.GroupName}")
            .ToListAsync();

        if (chatNames.Count > 0)
        {
            var chats = await db.Chats
                .Where(c => chatNames.Contains(c.Name) && c.IsAcademic == false && c.Type == "community")
                .ToListAsync();
            db.Chats.RemoveRange(chats);
            logger.LogInformation("Removing {Count} subject chat(s) for subject '{Name}'", chats.Count, subject.Name);
        }

        db.Subjects.Remove(subject); // каскадом удаляет TeacherSubjectGroups
        await db.SaveChangesAsync();

        logger.LogInformation("Admin deleted subject Id={Id} ('{Name}')", id, subject.Name);
        return NoContent();
    }

    // ── TEACHER ASSIGNMENTS ───────────────────────────────────────────────────

    /// GET /api/admin/people/{personId}/subjects
    [HttpGet("people/{personId:int}/subjects")]
    public async Task<IActionResult> GetTeacherSubjects(int personId)
    {
        if (!await db.People.AnyAsync(p => p.Id == personId))
            return NotFound(new { message = "Участник не найден" });

        var assignments = await db.TeacherSubjectGroups
            .Where(t => t.PersonId == personId)
            .Include(t => t.Subject)
            .OrderBy(t => t.Subject.Name).ThenBy(t => t.GroupName)
            .Select(t => new
            {
                id          = t.Id,
                subjectId   = t.SubjectId,
                subjectName = t.Subject.Name,
                groupName   = t.GroupName,
                chatId      = (Guid?)db.Chats
                    .Where(c => c.Name == t.Subject.Name + " " + t.GroupName
                             && c.Type == "community")
                    .Select(c => c.Id)
                    .FirstOrDefault()
            })
            .ToListAsync();

        return Ok(assignments);
    }

    /// POST /api/admin/people/{personId}/subjects
    /// Creates the assignment AND auto-creates the subject community chat.
    [HttpPost("people/{personId:int}/subjects")]
    public async Task<IActionResult> AssignSubject(int personId, [FromBody] AssignSubjectRequest req)
    {
        var person = await db.People.FindAsync(personId);
        if (person == null) return NotFound(new { message = "Участник не найден" });

        var subject = await db.Subjects.FindAsync(req.SubjectId);
        if (subject == null) return NotFound(new { message = "Предмет не найден" });

        if (string.IsNullOrWhiteSpace(req.GroupName))
            return BadRequest(new { message = "Название группы не может быть пустым" });

        var groupName = req.GroupName.Trim();

        if (await db.TeacherSubjectGroups.AnyAsync(t =>
                t.PersonId == personId && t.SubjectId == req.SubjectId && t.GroupName == groupName))
            return Conflict(new { message = "Такое назначение уже существует" });

        // 1. Сохраняем назначение
        var assignment = new TeacherSubjectGroup
        {
            PersonId  = personId,
            SubjectId = req.SubjectId,
            GroupName = groupName
        };
        db.TeacherSubjectGroups.Add(assignment);

        // 2. Создаём предметный чат-сообщество
        var chatName = $"{subject.Name} {groupName}";
        var chat = await CreateSubjectChatAsync(chatName, subject.Name, groupName, person);

        await db.SaveChangesAsync();

        logger.LogInformation(
            "Admin assigned person Id={PersonId} → subject '{Subject}' in group '{Group}', chat '{Chat}'",
            personId, subject.Name, groupName, chat.Id);

        return Ok(new
        {
            id          = assignment.Id,
            subjectId   = assignment.SubjectId,
            subjectName = subject.Name,
            groupName   = assignment.GroupName,
            chatId      = chat.Id
        });
    }

    /// DELETE /api/admin/people/{personId}/subjects/{assignmentId}
    /// Also deletes the associated subject community chat.
    [HttpDelete("people/{personId:int}/subjects/{assignmentId:int}")]
    public async Task<IActionResult> RemoveAssignment(int personId, int assignmentId)
    {
        var assignment = await db.TeacherSubjectGroups
            .Include(t => t.Subject)
            .FirstOrDefaultAsync(t => t.Id == assignmentId && t.PersonId == personId);
        if (assignment == null) return NotFound(new { message = "Назначение не найдено" });

        var chatName = $"{assignment.Subject.Name} {assignment.GroupName}";

        // Удаляем связанный чат
        var chat = await db.Chats
            .FirstOrDefaultAsync(c => c.Name == chatName && c.Type == "community");
        if (chat != null)
        {
            db.Chats.Remove(chat);
            logger.LogInformation("Removing subject chat '{Name}' (Id={Id})", chatName, chat.Id);
        }

        db.TeacherSubjectGroups.Remove(assignment);
        await db.SaveChangesAsync();

        logger.LogInformation("Admin removed assignment Id={Id}", assignmentId);
        return NoContent();
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /// <summary>
    /// Создаёт чат-сообщество для предмета+группы.
    /// Преподаватель становится создателем (если у него есть аккаунт).
    /// Все зарегистрированные студенты группы добавляются участниками.
    /// Не вызывает SaveChanges — только добавляет сущности в контекст.
    /// </summary>
    private async Task<Chat> CreateSubjectChatAsync(
        string chatName, string subjectName, string groupName, Person teacher)
    {
        // Если чат с таким именем уже существует — возвращаем его
        var existing = await db.Chats
            .FirstOrDefaultAsync(c => c.Name == chatName && c.Type == "community");
        if (existing != null)
            return existing;

        // Находим аккаунт преподавателя (может отсутствовать)
        User? teacherUser = teacher.UserId.HasValue
            ? await db.Users.FindAsync(teacher.UserId.Value)
            : null;

        var chat = new Chat
        {
            Name        = chatName,
            Type        = "community",
            IsAcademic  = false,
            AdminId     = teacherUser?.Id,
            Description = $"Предмет «{subjectName}» — группа {groupName}"
        };
        db.Chats.Add(chat);

        // Преподаватель — создатель
        if (teacherUser != null)
        {
            db.ChatMembers.Add(new ChatMember
            {
                ChatId = chat.Id,
                UserId = teacherUser.Id,
                Role   = "creator"
            });
        }

        // Все зарегистрированные студенты группы — участники
        var students = await db.Users
            .Where(u => u.Group == groupName && u.Role == "student"
                     && (teacherUser == null || u.Id != teacherUser.Id))
            .ToListAsync();

        foreach (var student in students)
        {
            db.ChatMembers.Add(new ChatMember
            {
                ChatId = chat.Id,
                UserId = student.Id,
                Role   = "member"
            });
        }

        logger.LogInformation(
            "Preparing subject chat '{Name}': teacher={HasTeacher}, students={Count}",
            chatName, teacherUser != null, students.Count);

        return chat;
    }
}

public class CreateSubjectRequest { public string? Name      { get; set; } }
public class AssignSubjectRequest { public int     SubjectId { get; set; }
                                    public string? GroupName { get; set; } }
