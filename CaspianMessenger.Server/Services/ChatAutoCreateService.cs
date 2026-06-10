using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.Models;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Services;

/// <summary>
/// Фоновый сервис, который при старте приложения автоматически создаёт:
///   — групповой чат для каждой учебной группы студентов (вкладка «Общение»)
///   — общий чат для всех преподавателей (вкладка «Академический»)
/// Если чат уже существует — просто добавляет новых участников, которых там ещё нет.
/// </summary>
public class ChatAutoCreateService(
    IServiceScopeFactory scopeFactory,
    ILogger<ChatAutoCreateService> logger) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            using var scope = scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            await EnsureAllStudentsChatAsync(db, cancellationToken);   // Общение
            await EnsureAcademicGroupChatsAsync(db, cancellationToken); // Академический — по группам
            await EnsureTeachersChatAsync(db, cancellationToken);       // Академический — преподаватели
            logger.LogInformation("ChatAutoCreateService: завершил инициализацию чатов");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "ChatAutoCreateService: ошибка при инициализации чатов");
        }
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    // ── Общий чат всех студентов (вкладка «Общение», IsAcademic = false) ─────

    private async Task EnsureAllStudentsChatAsync(AppDbContext db, CancellationToken ct)
    {
        const string chatName = "Общий чат студентов";

        var studentIds = await db.Users
            .Where(u => u.Role == "student")
            .Select(u => u.Id)
            .ToListAsync(ct);

        if (studentIds.Count == 0) return;

        var existingChatId = await db.Chats
            .Where(c => c.Name == chatName && c.Type == "group" && !c.IsAcademic)
            .Select(c => (Guid?)c.Id)
            .FirstOrDefaultAsync(ct);

        if (existingChatId == null)
        {
            var chat = new Chat
            {
                Name        = chatName,
                Type        = "group",
                IsAcademic  = false,
                Description = "Общий чат для всех студентов"
            };
            db.Chats.Add(chat);

            foreach (var (userId, idx) in studentIds.Select((id, i) => (id, i)))
            {
                db.ChatMembers.Add(new ChatMember
                {
                    ChatId = chat.Id,
                    UserId = userId,
                    Role   = idx == 0 ? "creator" : "member"
                });
            }

            await db.SaveChangesAsync(ct);
            logger.LogInformation("ChatAutoCreateService: создан «{Name}» ({Count} студентов)",
                chatName, studentIds.Count);
        }
        else
        {
            var existingMemberIds = await db.ChatMembers
                .Where(cm => cm.ChatId == existingChatId.Value)
                .Select(cm => cm.UserId)
                .ToListAsync(ct);

            var newMembers = studentIds.Except(existingMemberIds).ToList();
            if (newMembers.Count == 0) return;

            foreach (var userId in newMembers)
            {
                db.ChatMembers.Add(new ChatMember
                {
                    ChatId = existingChatId.Value,
                    UserId = userId,
                    Role   = "member"
                });
            }

            await db.SaveChangesAsync(ct);
            logger.LogInformation(
                "ChatAutoCreateService: добавлено {Count} новых студентов в «{Name}»",
                newMembers.Count, chatName);
        }
    }

    // ── Чаты учебных групп (вкладка «Академический», IsAcademic = true) ────────

    private async Task EnsureAcademicGroupChatsAsync(AppDbContext db, CancellationToken ct)
    {
        var students = await db.Users
            .Where(u => u.Role == "student" && u.Group != null && u.Group != "")
            .Select(u => new { u.Id, u.Group })
            .ToListAsync(ct);

        var groupNames = students.Select(s => s.Group!).Distinct().OrderBy(g => g).ToList();

        foreach (var groupName in groupNames)
        {
            var studentIds = students.Where(s => s.Group == groupName).Select(s => s.Id).ToList();

            var existingChatId = await db.Chats
                .Where(c => c.Name == groupName && c.Type == "group" && c.IsAcademic)
                .Select(c => (Guid?)c.Id)
                .FirstOrDefaultAsync(ct);

            if (existingChatId == null)
            {
                var chat = new Chat
                {
                    Name        = groupName,
                    Type        = "group",
                    IsAcademic  = true,
                    Description = $"Академический чат группы {groupName}"
                };
                db.Chats.Add(chat);

                foreach (var (userId, idx) in studentIds.Select((id, i) => (id, i)))
                    db.ChatMembers.Add(new ChatMember { ChatId = chat.Id, UserId = userId,
                        Role = idx == 0 ? "creator" : "member" });

                await db.SaveChangesAsync(ct);
                logger.LogInformation("ChatAutoCreateService: создан академический чат «{Group}»", groupName);
            }
            else
            {
                var existing = await db.ChatMembers
                    .Where(cm => cm.ChatId == existingChatId.Value)
                    .Select(cm => cm.UserId).ToListAsync(ct);

                var newMembers = studentIds.Except(existing).ToList();
                if (newMembers.Count == 0) continue;

                foreach (var userId in newMembers)
                    db.ChatMembers.Add(new ChatMember { ChatId = existingChatId.Value,
                        UserId = userId, Role = "member" });

                await db.SaveChangesAsync(ct);
                logger.LogInformation("ChatAutoCreateService: добавлено {Count} студентов в «{Group}»",
                    newMembers.Count, groupName);
            }
        }
    }

    // ── Чат преподавателей (вкладка «Академический», IsAcademic = true) ───────

    private async Task EnsureTeachersChatAsync(AppDbContext db, CancellationToken ct)
    {
        const string chatName = "Преподаватели";

        var teachers = await db.Users
            .Where(u => u.Role == "teacher")
            .Select(u => u.Id)
            .ToListAsync(ct);

        if (teachers.Count == 0) return;

        var existingChatId = await db.Chats
            .Where(c => c.Name == chatName && c.Type == "group" && c.IsAcademic)
            .Select(c => (Guid?)c.Id)
            .FirstOrDefaultAsync(ct);

        if (existingChatId == null)
        {
            var chat = new Chat
            {
                Name        = chatName,
                Type        = "group",
                IsAcademic  = true,
                Description = "Общий чат преподавателей"
            };
            db.Chats.Add(chat);

            foreach (var (userId, idx) in teachers.Select((id, i) => (id, i)))
            {
                db.ChatMembers.Add(new ChatMember
                {
                    ChatId = chat.Id,
                    UserId = userId,
                    Role   = idx == 0 ? "creator" : "member"
                });
            }

            await db.SaveChangesAsync(ct);
            logger.LogInformation("ChatAutoCreateService: создан чат «{Name}»", chatName);
        }
        else
        {
            // Добавляем новых преподавателей
            var existingMemberIds = await db.ChatMembers
                .Where(cm => cm.ChatId == existingChatId.Value)
                .Select(cm => cm.UserId)
                .ToListAsync(ct);

            var newTeachers = teachers.Except(existingMemberIds).ToList();
            if (newTeachers.Count == 0) return;

            foreach (var userId in newTeachers)
            {
                db.ChatMembers.Add(new ChatMember
                {
                    ChatId = existingChatId.Value,
                    UserId = userId,
                    Role   = "member"
                });
            }

            await db.SaveChangesAsync(ct);
            logger.LogInformation(
                "ChatAutoCreateService: добавлено {Count} новых преподавателей в «{Name}»",
                newTeachers.Count, chatName);
        }
    }
}
