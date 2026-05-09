using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/notifications")]
[Authorize]
public class NotificationsController(FcmService fcmService, AppDbContext db) : ControllerBase
{
    /// <summary>
    /// Регистрирует или обновляет FCM-токен для текущего пользователя.
    /// Поддерживает несколько устройств: каждый токен хранится отдельно.
    /// </summary>
    [HttpPut("fcm-token")]
    public async Task<IActionResult> RegisterFcmToken([FromBody] RegisterFcmTokenRequest request)
    {
        var userId = GetUserId();
        if (userId == Guid.Empty) return Unauthorized();

        await fcmService.RegisterTokenAsync(userId, request.Token, request.Platform);
        return NoContent();
    }

    /// <summary>
    /// Возвращает историю административных уведомлений для текущего пользователя.
    /// Фильтрует по роли: студент видит "all" + "students", преподаватель — "all" + "teachers".
    /// GET /api/notifications?page=1&pageSize=50
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetMyNotifications(
        [FromQuery] int page     = 1,
        [FromQuery] int pageSize = 50)
    {
        var userId = GetUserId();
        if (userId == Guid.Empty) return Unauthorized();

        var user = await db.Users.FindAsync(userId);
        if (user == null) return Unauthorized();

        if (page < 1) page = 1;
        pageSize = Math.Clamp(pageSize, 1, 100);

        var query = db.Notifications.AsQueryable();
        query = user.Role switch
        {
            "student" => query.Where(n => n.Target == "all" || n.Target == "students"),
            "teacher" => query.Where(n => n.Target == "all" || n.Target == "teachers"),
            _         => query // другие роли видят все
        };

        var items = await query
            .OrderByDescending(n => n.SentAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(n => new
            {
                id     = n.Id,
                title  = n.Title,
                body   = n.Body,
                target = n.Target,
                sentAt = n.SentAt
            })
            .ToListAsync();

        return Ok(items);
    }

    private Guid GetUserId()
    {
        var sub = User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                  ?? User.FindFirst("sub")?.Value;
        return Guid.TryParse(sub, out var id) ? id : Guid.Empty;
    }
}

public record RegisterFcmTokenRequest(
    [Required] string Token,
    string Platform = "android");
