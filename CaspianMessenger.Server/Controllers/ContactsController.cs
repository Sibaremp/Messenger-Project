using System.Security.Claims;
using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.DTOs;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/contacts")]
[Authorize]
public class ContactsController(AppDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetContacts()
    {
        var currentUserId = GetUserId();
        var users = await db.Users
            .Where(u => u.Id != currentUserId)
            .Select(u => new ContactDto
            {
                Id = u.Id,
                Name = u.Name,
                Group = u.Group,
                Phone = u.Phone,
                IsTeacher = u.Role == "teacher",
                AvatarPath = u.AvatarPath,
                IsOnline = u.IsOnline
            })
            .ToListAsync();

        return Ok(users);
    }

    private Guid GetUserId() =>
        Guid.Parse(User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                   ?? User.FindFirst("sub")!.Value);
}
