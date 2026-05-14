using BCrypt.Net;
using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.Helpers;
using CaspianMessenger.Server.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/admin")]
public class AdminController(
    AppDbContext db,
    JwtHelper jwtHelper,
    ImportService importService,
    ILogger<AdminController> logger) : ControllerBase
{
    // ── 0. ПЕРВИЧНАЯ НАСТРОЙКА ────────────────────────────────────────────────

    /// <summary>
    /// Создаёт первого администратора. Работает ТОЛЬКО если таблица Admins пуста.
    /// После создания первого аккаунта endpoint перестаёт отвечать (403).
    /// </summary>
    [HttpPost("setup")]
    [AllowAnonymous]
    public async Task<IActionResult> Setup([FromBody] AdminLoginRequest req)
    {
        if (await db.Admins.AnyAsync())
            return StatusCode(403, new { message = "Первичная настройка уже выполнена" });

        if (string.IsNullOrWhiteSpace(req.Login) || req.Login.Length < 3)
            return BadRequest(new { message = "Логин должен содержать минимум 3 символа" });

        if (string.IsNullOrWhiteSpace(req.Password) || req.Password.Length < 6)
            return BadRequest(new { message = "Пароль должен содержать минимум 6 символов" });

        var admin = new CaspianMessenger.Server.Models.Admin
        {
            Login        = req.Login.Trim(),
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.Password, workFactor: 11)
        };

        db.Admins.Add(admin);
        await db.SaveChangesAsync();

        logger.LogInformation("First admin account '{Login}' created via /api/admin/setup", admin.Login);
        return Ok(new { message = "Администратор создан", login = admin.Login });
    }

    // ── 1. AUTH ──────────────────────────────────────────────────────────────

    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<IActionResult> Login([FromBody] AdminLoginRequest req)
    {
        var admin = await db.Admins
            .FirstOrDefaultAsync(a => a.Login == req.Login);

        bool passwordValid = false;
        if (admin != null)
            try { passwordValid = BCrypt.Net.BCrypt.Verify(req.Password, admin.PasswordHash); }
            catch { passwordValid = false; }

        if (!passwordValid)
        {
            logger.LogWarning("Admin login failed for '{Login}'", req.Login);
            return Unauthorized(new { message = "Неверный логин или пароль" });
        }

        var token = jwtHelper.GenerateAdminToken(admin!.Login);
        logger.LogInformation("Admin '{Login}' logged in", admin.Login);
        return Ok(new { token });
    }

    // ── 1b. УПРАВЛЕНИЕ АДМИНИСТРАТОРАМИ ──────────────────────────────────────

    /// GET /api/admin/admins → список аккаунтов администраторов
    [HttpGet("admins")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> GetAdmins()
    {
        var admins = await db.Admins
            .OrderBy(a => a.Id)
            .Select(a => new { a.Id, a.Login })
            .ToListAsync();
        return Ok(admins);
    }

    /// POST /api/admin/admins — создать нового администратора
    [HttpPost("admins")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> CreateAdmin([FromBody] AdminLoginRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Login) || req.Login.Length < 3)
            return BadRequest(new { message = "Логин должен содержать минимум 3 символа" });

        if (string.IsNullOrWhiteSpace(req.Password) || req.Password.Length < 6)
            return BadRequest(new { message = "Пароль должен содержать минимум 6 символов" });

        if (await db.Admins.AnyAsync(a => a.Login == req.Login.Trim()))
            return Conflict(new { message = "Логин уже занят" });

        var admin = new CaspianMessenger.Server.Models.Admin
        {
            Login        = req.Login.Trim(),
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.Password, workFactor: 11)
        };
        db.Admins.Add(admin);
        await db.SaveChangesAsync();

        logger.LogInformation("Admin '{Creator}' created new admin account '{Login}'",
            User.FindFirst("name")?.Value, admin.Login);
        return CreatedAtAction(nameof(GetAdmins), new { admin.Id, admin.Login });
    }

    /// DELETE /api/admin/admins/{id}
    [HttpDelete("admins/{id:int}")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> DeleteAdmin(int id)
    {
        var admin = await db.Admins.FindAsync(id);
        if (admin == null) return NotFound(new { message = "Администратор не найден" });

        if (await db.Admins.CountAsync() <= 1)
            return BadRequest(new { message = "Нельзя удалить последнего администратора" });

        db.Admins.Remove(admin);
        await db.SaveChangesAsync();

        logger.LogInformation("Admin account '{Login}' (Id={Id}) deleted", admin.Login, id);
        return NoContent();
    }

    // ── 2. USERS ─────────────────────────────────────────────────────────────

    /// GET /api/admin/users → [{id, login, role, group, phone, firstName, lastName, middleName}]
    [HttpGet("users")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> GetUsers()
    {
        var users = await db.Users
            .OrderBy(u => u.Seq)
            .Select(u => new
            {
                id         = u.Seq,
                login      = u.Name,
                role       = u.Role,
                group      = u.Group,
                phone      = u.Phone,
                // ФИО из связанного Person (null если нет привязки)
                firstName  = db.People
                    .Where(p => p.UserId == u.Id)
                    .Select(p => p.FirstName)
                    .FirstOrDefault(),
                lastName   = db.People
                    .Where(p => p.UserId == u.Id)
                    .Select(p => p.LastName)
                    .FirstOrDefault(),
                middleName = db.People
                    .Where(p => p.UserId == u.Id)
                    .Select(p => p.MiddleName)
                    .FirstOrDefault(),
            })
            .ToListAsync();

        return Ok(users);
    }

    /// PUT /api/admin/users/{id}
    [HttpPut("users/{id:int}")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> UpdateUser(int id, [FromBody] UpdateUserRequest req)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Seq == id);
        if (user == null) return NotFound(new { message = "Пользователь не найден" });

        if (!string.IsNullOrWhiteSpace(req.Login) && req.Login.Trim() != user.Name)
        {
            var taken = await db.Users.AnyAsync(u => u.Name == req.Login.Trim() && u.Seq != id);
            if (taken) return Conflict(new { message = "Логин уже занят" });
            user.Name = req.Login.Trim();
        }

        if (!string.IsNullOrWhiteSpace(req.Role))
            user.Role = req.Role.Trim();

        user.Group = string.IsNullOrWhiteSpace(req.Group) ? null : req.Group.Trim();
        user.Phone = string.IsNullOrWhiteSpace(req.Phone) ? null : req.Phone.Trim();

        await db.SaveChangesAsync();
        logger.LogInformation("Admin updated user Seq={Seq}", id);
        return Ok(new { id = user.Seq, login = user.Name, role = user.Role, group = user.Group, phone = user.Phone });
    }

    /// PUT /api/admin/users/{id}/password
    [HttpPut("users/{id:int}/password")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> ChangeUserPassword(int id, [FromBody] ChangePasswordRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.NewPassword) || req.NewPassword.Length < 6)
            return BadRequest(new { message = "Пароль должен содержать минимум 6 символов" });

        var user = await db.Users.FirstOrDefaultAsync(u => u.Seq == id);
        if (user == null) return NotFound(new { message = "Пользователь не найден" });

        user.PasswordHash = PasswordHelper.Hash(req.NewPassword);
        await db.SaveChangesAsync();

        // Инвалидируем все активные сессии пользователя
        var sessions = await db.Sessions
            .Where(s => s.UserId == user.Id && s.IsActive)
            .ToListAsync();
        foreach (var s in sessions) s.IsActive = false;
        await db.SaveChangesAsync();

        logger.LogInformation("Admin changed password for user Seq={Seq} ({Name}), {Count} sessions invalidated",
            id, user.Name, sessions.Count);
        return Ok(new { message = "Пароль изменён", sessionsInvalidated = sessions.Count });
    }

    /// DELETE /api/admin/users/{id}  (id = User.Seq)
    [HttpDelete("users/{id:int}")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> DeleteUser(int id)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Seq == id);
        if (user == null) return NotFound(new { message = "Пользователь не найден" });

        db.Users.Remove(user);
        await db.SaveChangesAsync();

        logger.LogInformation("Admin deleted user Seq={Seq} ({Name})", id, user.Name);
        return NoContent();
    }

    // ── 3. PEOPLE ─────────────────────────────────────────────────────────────

    /// GET /api/admin/people?search=&role=&group=&hasUser=
    [HttpGet("people")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> GetPeople(
        [FromQuery] string? search,
        [FromQuery] string? role,
        [FromQuery] string? group,
        [FromQuery] bool?   hasUser)
    {
        var query = db.People.AsQueryable();

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(p =>
                p.LastName.ToLower().Contains(s)  ||
                p.FirstName.ToLower().Contains(s) ||
                (p.MiddleName != null && p.MiddleName.ToLower().Contains(s)));
        }

        if (!string.IsNullOrWhiteSpace(role) && role != "all")
            query = query.Where(p => p.Role == role);

        if (!string.IsNullOrWhiteSpace(group))
            query = query.Where(p => p.Group == group);

        if (hasUser.HasValue)
            query = query.Where(p => hasUser.Value ? p.UserId != null : p.UserId == null);

        var people = await query
            .OrderBy(p => p.LastName).ThenBy(p => p.FirstName)
            .Select(p => new
            {
                id         = p.Id,
                firstName  = p.FirstName,
                lastName   = p.LastName,
                middleName = p.MiddleName,
                role       = p.Role,
                group      = p.Group,
                hasUser    = p.UserId != null
            })
            .ToListAsync();

        return Ok(people);
    }

    /// PUT /api/admin/people/{id}
    [HttpPut("people/{id:int}")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> UpdatePerson(int id, [FromBody] UpdatePersonRequest req)
    {
        var person = await db.People.FindAsync(id);
        if (person == null) return NotFound(new { message = "Участник не найден" });

        if (!string.IsNullOrWhiteSpace(req.FirstName))  person.FirstName  = req.FirstName.Trim();
        if (!string.IsNullOrWhiteSpace(req.LastName))   person.LastName   = req.LastName.Trim();
        person.MiddleName = string.IsNullOrWhiteSpace(req.MiddleName) ? null : req.MiddleName.Trim();

        if (!string.IsNullOrWhiteSpace(req.Role))
            person.Role = req.Role.Trim().ToLowerInvariant() is "teacher" or "преподаватель"
                ? "teacher" : "student";

        person.Group = string.IsNullOrWhiteSpace(req.Group) ? null : req.Group.Trim();

        await db.SaveChangesAsync();
        logger.LogInformation("Admin updated person Id={Id}", id);
        return Ok(new
        {
            id         = person.Id,
            firstName  = person.FirstName,
            lastName   = person.LastName,
            middleName = person.MiddleName,
            role       = person.Role,
            group      = person.Group,
            hasUser    = person.UserId != null
        });
    }

    /// DELETE /api/admin/people/{id}
    [HttpDelete("people/{id:int}")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> DeletePerson(int id)
    {
        var person = await db.People.FindAsync(id);
        if (person == null) return NotFound(new { message = "Участник не найден" });

        db.People.Remove(person);
        await db.SaveChangesAsync();

        logger.LogInformation("Admin deleted person Id={Id} ({LastName} {FirstName})", id, person.LastName, person.FirstName);
        return NoContent();
    }

    // ── 4. IMPORT ─────────────────────────────────────────────────────────────

    /// POST /api/admin/import-people  (multipart/form-data, field: file)
    [HttpPost("import-people")]
    [Authorize(Policy = "AdminOnly")]
    [RequestSizeLimit(10_485_760)] // 10 MB
    public async Task<IActionResult> ImportPeople(IFormFile file)
    {
        if (file is null || file.Length == 0)
            return BadRequest(new { message = "Файл не передан" });

        try
        {
            var (added, skipped) = await importService.ImportPeopleAsync(file);
            return Ok(new { added, skipped });
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Import failed");
            return StatusCode(500, new { message = "Ошибка при импорте файла" });
        }
    }
}

public record AdminLoginRequest(string Login, string Password);

public class ChangePasswordRequest
{
    public string? NewPassword { get; set; }
}

public class UpdateUserRequest
{
    public string? Login  { get; set; }
    public string? Role   { get; set; }
    public string? Group  { get; set; }
    public string? Phone  { get; set; }
}

public class UpdatePersonRequest
{
    public string? FirstName  { get; set; }
    public string? LastName   { get; set; }
    public string? MiddleName { get; set; }
    public string? Role       { get; set; }
    public string? Group      { get; set; }
}
