using System.Security.Claims;
using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/files")]
[Authorize]
public class FilesController(FileService fileService, AppDbContext db) : ControllerBase
{
    [HttpPost("upload")]
    [RequestSizeLimit(52_428_800)] // 50 MB
    public async Task<IActionResult> Upload(IFormFile file)
    {
        var (response, error) = await fileService.UploadFileAsync(file);
        if (error != null) return BadRequest(new { message = error });
        return Ok(response);
    }

    /// <summary>POST /api/messages/upload-audio — загрузка голосового сообщения.</summary>
    [HttpPost("/api/messages/upload-audio")]
    [RequestSizeLimit(10_485_760)] // 10 MB
    public async Task<IActionResult> UploadAudio(IFormFile file)
    {
        if (file is null || file.Length == 0)
            return BadRequest(new { message = "Файл не передан" });

        var (url, error) = await fileService.UploadAudioAsync(file);
        if (error != null) return BadRequest(new { message = error });

        var baseUrl = $"{Request.Scheme}://{Request.Host}";
        return Ok(new { url = baseUrl + url });
    }

    [HttpGet("search")]
    public async Task<IActionResult> SearchFiles([FromQuery] string q, [FromQuery] string? type)
    {
        var userId = GetUserId();
        var chatIds = await db.ChatMembers
            .Where(cm => cm.UserId == userId)
            .Select(cm => cm.ChatId)
            .ToListAsync();

        var query = db.Attachments
            .Where(a => a.MessageId != null)
            .Where(a => a.FileName.Contains(q))
            .Where(a => a.Message != null && chatIds.Contains(a.Message.ChatId));

        if (!string.IsNullOrEmpty(type))
            query = query.Where(a => a.Type == type);

        var results = await query
            .Include(a => a.Message).ThenInclude(m => m!.Chat)
            .Take(50)
            .ToListAsync();

        return Ok(results.Select(a => new
        {
            chat = new { a.Message!.Chat.Id, a.Message.Chat.Name },
            message = new { a.MessageId },
            attachment = new
            {
                a.Id,
                path = a.FilePath,
                a.FileName,
                a.FileSize,
                a.Type,
                a.MimeType
            }
        }));
    }

    private Guid GetUserId() =>
        Guid.Parse(User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                   ?? User.FindFirst("sub")!.Value);
}
