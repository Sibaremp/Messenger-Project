using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.DTOs.Auth;
using CaspianMessenger.Server.Helpers;
using CaspianMessenger.Server.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;

namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController(
    AppDbContext db,
    AuthService authService,
    SessionService sessionService) : ControllerBase
{
    // ── Регистрация / Вход ────────────────────────────────────────────────────

    [HttpPost("register")]
    [AllowAnonymous]
    public async Task<IActionResult> Register([FromBody] RegisterRequest req)
    {
        var (success, error, response) = await authService.RegisterAsync(req);
        if (!success)
        {
            if (error!.Contains("taken"))           return Conflict(new { message = error });
            if (error!.Contains("already has"))     return Conflict(new { message = "Этот участник уже зарегистрирован" });
            if (error!.Contains("Person not found")) return BadRequest(new { message = "Участник не найден" });
            return BadRequest(new { message = error });
        }

        await sessionService.CreateSessionAsync(
            response!.Id,
            response.Token,
            Request.Headers.UserAgent.ToString(),
            HttpContext.Connection.RemoteIpAddress?.ToString());

        return CreatedAtAction(nameof(Register), response);
    }

    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<IActionResult> Login([FromBody] LoginRequest req)
    {
        var (success, error, response) = await authService.LoginAsync(req);
        if (!success) return Unauthorized(new { message = error });

        await sessionService.CreateSessionAsync(
            response!.Id,
            response.Token,
            Request.Headers.UserAgent.ToString(),
            HttpContext.Connection.RemoteIpAddress?.ToString());

        return Ok(response);
    }

    // ── Справочники для регистрации (публичные) ───────────────────────────────

    /// <summary>
    /// Возвращает список групп, в которых есть хотя бы один
    /// незарегистрированный участник (Person.UserId == null).
    /// Используется на экране регистрации для заполнения выпадающего списка.
    /// </summary>
    [HttpGet("groups")]
    [AllowAnonymous]
    public async Task<IActionResult> GetGroups()
    {
        var groups = await db.People
            .Where(p => p.UserId == null && p.Group != null)
            .Select(p => p.Group!)
            .Distinct()
            .OrderBy(g => g)
            .ToListAsync();

        return Ok(groups);
    }

    /// <summary>
    /// Возвращает незарегистрированных участников для выбора при регистрации.
    /// Фильтры: role (student | teacher), group.
    /// </summary>
    [HttpGet("people")]
    [AllowAnonymous]
    public async Task<IActionResult> GetAvailablePeople(
        [FromQuery] string? group,
        [FromQuery] string? role)
    {
        var query = db.People.Where(p => p.UserId == null);

        if (!string.IsNullOrWhiteSpace(role))
            query = query.Where(p => p.Role == role);

        if (!string.IsNullOrWhiteSpace(group))
            query = query.Where(p => p.Group == group);

        var people = await query
            .OrderBy(p => p.LastName).ThenBy(p => p.FirstName)
            .Select(p => new
            {
                id         = p.Id,
                firstName  = p.FirstName,
                lastName   = p.LastName,
                middleName = p.MiddleName,
                role       = p.Role,
                group      = p.Group
            })
            .ToListAsync();

        return Ok(people);
    }

    // ── Сессии ────────────────────────────────────────────────────────────────

    [HttpGet("sessions")]
    [Authorize]
    public async Task<IActionResult> GetSessions()
    {
        var userId = GetUserId();
        var token  = GetToken();
        if (token == null) return Unauthorized();
        var sessions = await sessionService.GetUserSessionsAsync(userId, token);
        return Ok(sessions);
    }

    [HttpDelete("sessions/{sessionId:guid}")]
    [Authorize]
    public async Task<IActionResult> TerminateSession(Guid sessionId)
    {
        var userId = GetUserId();
        var token  = GetToken();
        if (token == null) return Unauthorized();
        var (success, error) = await sessionService.TerminateSessionAsync(sessionId, userId, token!);
        if (error == "Forbidden") return Forbid();
        if (!success) return NotFound(new { message = error });
        return NoContent();
    }

    [HttpDelete("sessions")]
    [Authorize]
    public async Task<IActionResult> TerminateAllSessions()
    {
        var userId = GetUserId();
        var token  = GetToken();
        if (token == null) return Unauthorized();
        await sessionService.TerminateAllSessionsAsync(userId, token!);
        return NoContent();
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private Guid GetUserId() =>
        Guid.Parse(User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                   ?? User.FindFirst("sub")!.Value);

    private string? GetToken() =>
        Request.Headers.Authorization.ToString().Replace("Bearer ", "").NullIfEmpty();
}
