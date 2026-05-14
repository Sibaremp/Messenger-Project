using System.Security.Claims;
using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.DTOs.Auth;
using CaspianMessenger.Server.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/users")]
[Authorize]
public class UsersController(AppDbContext db, FileService fileService) : ControllerBase
{
    [HttpGet("me")]
    public async Task<IActionResult> GetMe()
    {
        var userId = GetUserId();
        var user   = await db.Users.FindAsync(userId);
        if (user == null) return NotFound();

        var person = await db.People.FirstOrDefaultAsync(p => p.UserId == userId);
        return Ok(new AuthResponse
        {
            Id          = user.Id,
            Login       = user.Name,   // явный логин — никогда не перепутается с ФИО
            Name        = user.Name,   // обратная совместимость
            Role        = user.Role,
            Group       = user.Group,
            Phone       = user.Phone,
            Email       = user.Email,
            AvatarPath  = user.AvatarPath,
            AvatarUrl   = user.AvatarPath,
            Description = user.Description,
            Bio         = user.Description,
            IsOnline    = user.IsOnline,
            LastSeen    = user.LastSeen,
            Token       = "",
            FirstName   = person?.FirstName,
            LastName    = person?.LastName,
            MiddleName  = person?.MiddleName,
        });
    }

    [HttpPut("me")]
    public async Task<IActionResult> UpdateMe([FromBody] UpdateProfileRequest req)
    {
        var userId = GetUserId();
        var user   = await db.Users.FindAsync(userId);
        if (user == null) return NotFound();

        // Логин (user.Name) намеренно НЕ обновляется через этот эндпоинт,
        // чтобы пользователь не мог случайно перезаписать его через поле «Имя».
        if (req.Phone != null)      user.Phone       = req.Phone;
        if (req.Email != null)      user.Email       = req.Email;
        if (req.Bio != null)        user.Description = req.Bio;
        if (req.Description != null) user.Description = req.Description;
        if (req.AvatarUrl != null)  user.AvatarPath  = req.AvatarUrl;
        if (req.AvatarPath != null) user.AvatarPath  = req.AvatarPath;

        await db.SaveChangesAsync();

        var person = await db.People.FirstOrDefaultAsync(p => p.UserId == userId);
        return Ok(new
        {
            user.Id,
            Login      = user.Name,   // явный логин
            Name       = user.Name,   // обратная совместимость
            user.Role, user.Group, user.Phone, user.Email,
            AvatarPath = user.AvatarPath, AvatarUrl = user.AvatarPath,
            Description = user.Description, Bio = user.Description,
            FirstName  = person?.FirstName,
            LastName   = person?.LastName,
            MiddleName = person?.MiddleName,
        });
    }

    [HttpPost("me/avatar")]
    [RequestSizeLimit(10_485_760)] // 10 MB
    public async Task<IActionResult> UploadAvatar(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { message = "Файл не передан" });

        var userId = GetUserId();
        var user = await db.Users.FindAsync(userId);
        if (user == null) return NotFound();

        var (response, error) = await fileService.UploadFileAsync(file);
        if (error != null) return BadRequest(new { message = error });

        user.AvatarPath = response!.Path;
        await db.SaveChangesAsync();

        return Ok(new {
            user.Id, user.Name, user.Role, user.Group, user.Phone, user.Email,
            AvatarPath = user.AvatarPath, AvatarUrl = user.AvatarPath,
            Description = user.Description, Bio = user.Description,
            user.IsOnline, user.LastSeen
        });
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetUser(Guid id)
    {
        var user = await db.Users.FindAsync(id);
        if (user == null) return NotFound();
        return Ok(new { user.Id, user.Name, user.Group, user.AvatarPath, user.Description, user.IsOnline, user.LastSeen });
    }

    private Guid GetUserId() =>
        Guid.Parse(User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                   ?? User.FindFirst("sub")!.Value);
}

public class UpdateProfileRequest
{
    public string? Name { get; set; }
    public string? Phone { get; set; }
    [System.ComponentModel.DataAnnotations.EmailAddress] public string? Email { get; set; }
    public string? Bio { get; set; }         // Flutter использует bio
    public string? Description { get; set; } // альтернативное название
    public string? AvatarUrl { get; set; }   // Flutter использует avatarUrl
    public string? AvatarPath { get; set; }  // альтернативное название
}
