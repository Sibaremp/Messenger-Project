using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.DTOs.Auth;
using CaspianMessenger.Server.Helpers;
using CaspianMessenger.Server.Models;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Services;

public class AuthService(AppDbContext db, JwtHelper jwt, ILogger<AuthService> logger)
{
    public async Task<(bool Success, string? Error, AuthResponse? Response)> RegisterAsync(RegisterRequest req)
    {
        // ── 1. Проверяем логин ────────────────────────────────────────────────
        if (await db.Users.AnyAsync(u => u.Name == req.Name))
            return (false, "Name already taken", null);

        // ── 2. Находим и проверяем Person ─────────────────────────────────────
        var person = await db.People.FindAsync(req.PersonId);
        if (person == null)
            return (false, "Person not found", null);
        if (person.UserId != null)
            return (false, "Person already has an account", null);

        // ── 3. Создаём пользователя (role/group из Person) ────────────────────
        var user = new User
        {
            Name         = req.Name,
            PasswordHash = PasswordHelper.Hash(req.Password),
            Role         = person.Role,
            Group        = person.Group,
            Phone        = req.Phone,
            Email        = req.Email
        };
        db.Users.Add(user);

        // ── 4. Связываем Person → User ────────────────────────────────────────
        person.UserId = user.Id;

        // ── 5. Готовим участие в групповом и предметных чатах (БЕЗ SaveChanges) ──
        if (!string.IsNullOrWhiteSpace(person.Group))
        {
            await PrepareGroupChatAsync(user, person.Group);
            await PrepareSubjectChatsAsync(user, person.Group, person.Role);
        }

        // ── 6. Единственный SaveChanges на всю регистрацию ────────────────────
        await db.SaveChangesAsync();

        var token = jwt.GenerateToken(user);
        logger.LogInformation("User '{Name}' registered (PersonId={PersonId}, Group={Group})",
            user.Name, person.Id, person.Group);

        return (true, null, MapToResponse(user, token, person));
    }

    public async Task<(bool Success, string? Error, AuthResponse? Response)> LoginAsync(LoginRequest req)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Name == req.Name);
        if (user == null || !PasswordHelper.Verify(req.Password, user.PasswordHash))
            return (false, "Invalid name or password", null);

        user.IsOnline = true;
        await db.SaveChangesAsync();

        var person = await db.People.FirstOrDefaultAsync(p => p.UserId == user.Id);
        var token  = jwt.GenerateToken(user);
        return (true, null, MapToResponse(user, token, person));
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /// <summary>
    /// Подготавливает участие нового пользователя в академическом чате группы.
    /// Если чат не существует — создаёт его и добавляет уже зарегистрированных
    /// участников. Не вызывает SaveChanges — только готовит сущности в контексте.
    /// </summary>
    private async Task PrepareGroupChatAsync(User newUser, string group)
    {
        try
        {
            var chat = await db.Chats
                .Include(c => c.Members)
                .FirstOrDefaultAsync(c => c.IsAcademic && c.Name == group);

            if (chat == null)
            {
                // Создаём новый академический чат для группы
                chat = new Chat
                {
                    Name       = group,
                    Type       = "group",
                    IsAcademic = true
                };
                db.Chats.Add(chat);

                // Добавляем всех уже зарегистрированных участников этой группы
                var existingUsers = await db.Users
                    .Where(u => u.Group == group && u.Id != newUser.Id)
                    .ToListAsync();

                foreach (var u in existingUsers)
                    db.ChatMembers.Add(new ChatMember
                        { ChatId = chat.Id, UserId = u.Id, Role = "member" });

                logger.LogInformation(
                    "Preparing academic chat for group '{Group}' with {Count} existing members",
                    group, existingUsers.Count);
            }

            // Добавляем нового пользователя если ещё не состоит
            var alreadyMember = chat.Members.Any(m => m.UserId == newUser.Id);
            if (!alreadyMember)
                db.ChatMembers.Add(new ChatMember
                    { ChatId = chat.Id, UserId = newUser.Id, Role = "member" });
        }
        catch (Exception ex)
        {
            // Не прерываем регистрацию из-за ошибки синхронизации чата
            logger.LogError(ex, "Failed to prepare group chat for user '{Name}', group '{Group}'",
                newUser.Name, group);
        }
    }

    /// <summary>
    /// Добавляет нового пользователя во все предметные чаты-сообщества его группы.
    /// Для студента — во все чаты группы (каждый предмет).
    /// Для преподавателя — во все чаты, где он является создателем (назначение уже сделано через AdminSubjectsController).
    /// Не вызывает SaveChanges.
    /// </summary>
    private async Task PrepareSubjectChatsAsync(User newUser, string group, string role)
    {
        try
        {
            if (role == "student")
            {
                // Ищем все community-чаты этой группы (название оканчивается на " {group}")
                var suffix = $" {group}";
                var chats = await db.Chats
                    .Include(c => c.Members)
                    .Where(c => c.Type == "community" && c.Name.EndsWith(suffix))
                    .ToListAsync();

                foreach (var chat in chats)
                {
                    if (chat.Members.Any(m => m.UserId == newUser.Id)) continue;
                    db.ChatMembers.Add(new ChatMember
                    {
                        ChatId = chat.Id,
                        UserId = newUser.Id,
                        Role   = "member"
                    });
                }

                logger.LogInformation(
                    "Preparing {Count} subject chat(s) for student '{Name}', group '{Group}'",
                    chats.Count, newUser.Name, group);
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex,
                "Failed to prepare subject chats for user '{Name}', group '{Group}'",
                newUser.Name, group);
        }
    }

    private static AuthResponse MapToResponse(User user, string token, Person? person = null) => new()
    {
        Id          = user.Id,
        Login       = user.Name,
        Name        = user.Name,  // backward compat
        Role        = user.Role,
        Group       = user.Group,
        Phone       = user.Phone,
        AvatarPath  = user.AvatarPath,
        AvatarUrl   = user.AvatarPath,
        Description = user.Description,
        Bio         = user.Description,
        Email       = user.Email,
        IsOnline    = user.IsOnline,
        LastSeen    = user.LastSeen,
        Token       = token,
        FirstName   = person?.FirstName,
        LastName    = person?.LastName,
        MiddleName  = person?.MiddleName,
    };
}
