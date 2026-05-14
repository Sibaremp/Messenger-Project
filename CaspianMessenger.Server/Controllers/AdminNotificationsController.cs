using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.Hubs;
using CaspianMessenger.Server.Models;
using CaspianMessenger.Server.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/admin/notifications")]
[Authorize(Policy = "AdminOnly")]
public class AdminNotificationsController(
    AppDbContext db,
    FcmService fcm,
    IHubContext<ChatHub> hub,
    ILogger<AdminNotificationsController> logger) : ControllerBase
{
    // ── SEND ─────────────────────────────────────────────────────────────────

    /// POST /api/admin/notifications
    /// Body: { title, body, target }   target = "all" | "students" | "teachers"
    [HttpPost]
    public async Task<IActionResult> Send([FromBody] SendNotificationRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Title))
            return BadRequest(new { message = "Заголовок не может быть пустым" });
        if (string.IsNullOrWhiteSpace(req.Body))
            return BadRequest(new { message = "Текст уведомления не может быть пустым" });

        var target = (req.Target ?? "all").Trim().ToLowerInvariant();
        if (target is not ("all" or "students" or "teachers"))
            return BadRequest(new { message = "target должен быть: all, students или teachers" });

        // 1. Определяем получателей по роли
        var usersQuery = db.Users.AsQueryable();
        if (target == "students")
            usersQuery = usersQuery.Where(u => u.Role == "student");
        else if (target == "teachers")
            usersQuery = usersQuery.Where(u => u.Role == "teacher");

        var userIds = await usersQuery.Select(u => u.Id).ToListAsync();

        // 2. Собираем FCM-токены
        var tokens = await db.UserDevices
            .Where(d => userIds.Contains(d.UserId))
            .Select(d => d.FcmToken)
            .Distinct()
            .ToListAsync();

        // 3. Отправляем через SignalR (для подключённых клиентов)
        var signalRPayload = new
        {
            type   = "admin_notification",
            title  = req.Title.Trim(),
            body   = req.Body.Trim(),
            target,
            sentAt = DateTime.UtcNow
        };
        foreach (var uid in userIds)
            await hub.Clients.Group(uid.ToString()).SendAsync("ReceiveEvent", signalRPayload);

        // 4. Отправляем через FCM (для фоновых/отключённых клиентов)
        var data = new Dictionary<string, string>
        {
            ["type"]   = "admin_notification",
            ["title"]  = req.Title.Trim(),
            ["body"]   = req.Body.Trim(),
            ["target"] = target
        };
        if (!string.IsNullOrWhiteSpace(req.ImageUrl))
            data["imageUrl"] = req.ImageUrl.Trim();
        await fcm.SendToMultipleAsync(tokens, data);

        // 5. Сохраняем в историю
        var notification = new Notification
        {
            Title     = req.Title.Trim(),
            Body      = req.Body.Trim(),
            Target    = target,
            SentCount = tokens.Count
        };
        db.Notifications.Add(notification);
        await db.SaveChangesAsync();

        logger.LogInformation(
            "Admin sent notification '{Title}' to target='{Target}', {Count} tokens",
            notification.Title, target, tokens.Count);

        return Ok(new
        {
            id        = notification.Id,
            title     = notification.Title,
            body      = notification.Body,
            target    = notification.Target,
            createdAt = notification.SentAt,
            sentCount = notification.SentCount
        });
    }

    // ── HISTORY ───────────────────────────────────────────────────────────────

    /// GET /api/admin/notifications?page=1&pageSize=20
    [HttpGet]
    public async Task<IActionResult> GetHistory(
        [FromQuery] int page     = 1,
        [FromQuery] int pageSize = 20)
    {
        if (page < 1) page = 1;
        pageSize = Math.Clamp(pageSize, 1, 100);

        var total = await db.Notifications.CountAsync();

        var items = await db.Notifications
            .OrderByDescending(n => n.SentAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(n => new
            {
                id        = n.Id,
                title     = n.Title,
                body      = n.Body,
                target    = n.Target,
                createdAt = n.SentAt,
                sentCount = n.SentCount
            })
            .ToListAsync();

        return Ok(items);
    }

    /// DELETE /api/admin/notifications/{id}
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> DeleteNotification(int id)
    {
        var notification = await db.Notifications.FindAsync(id);
        if (notification == null) return NotFound(new { message = "Уведомление не найдено" });

        db.Notifications.Remove(notification);
        await db.SaveChangesAsync();

        return NoContent();
    }

    // ── UPLOAD ATTACHMENT ─────────────────────────────────────────────────────

    /// POST /api/admin/notifications/upload  (multipart/form-data, field: file)
    [HttpPost("upload")]
    [RequestSizeLimit(52_428_800)] // 50 MB
    public async Task<IActionResult> UploadAttachment(IFormFile file)
    {
        if (file is null || file.Length == 0)
            return BadRequest(new { message = "Файл не передан" });

        var allowedTypes = new[] { "image/", "video/", "image/gif" };
        if (!allowedTypes.Any(t => file.ContentType.StartsWith(t)))
            return BadRequest(new { message = "Разрешены только изображения и видео" });

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        var fileName = $"{Guid.NewGuid()}{ext}";
        var folder = Path.Combine("wwwroot", "uploads", "notifications");
        Directory.CreateDirectory(folder);
        var filePath = Path.Combine(folder, fileName);

        await using var stream = System.IO.File.Create(filePath);
        await file.CopyToAsync(stream);

        var baseUrl = $"{Request.Scheme}://{Request.Host}";
        var url = $"{baseUrl}/uploads/notifications/{fileName}";

        return Ok(new { url, fileName = file.FileName, fileSize = file.Length, contentType = file.ContentType });
    }
}

public class SendNotificationRequest
{
    public string? Title    { get; set; }
    public string? Body     { get; set; }
    public string? Target   { get; set; }
    public string? ImageUrl { get; set; }
}
