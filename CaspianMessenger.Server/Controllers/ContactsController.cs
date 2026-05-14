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
            .ToListAsync();

        var userIds = users.Select(u => u.Id).ToList();
        var persons = await db.People
            .Where(p => p.UserId != null && userIds.Contains(p.UserId!.Value))
            .ToListAsync();
        var personMap = persons
            .Where(p => p.UserId.HasValue)
            .ToDictionary(p => p.UserId!.Value);

        var result = users.Select(u =>
        {
            personMap.TryGetValue(u.Id, out var person);
            var displayName = person != null
                ? string.Join(" ", new[] { person.LastName, person.FirstName, person.MiddleName }
                    .Where(s => !string.IsNullOrWhiteSpace(s)))
                : null;

            return new ContactDto
            {
                Id = u.Id,
                Name = u.Name,
                DisplayName = string.IsNullOrWhiteSpace(displayName) ? null : displayName,
                Group = u.Group,
                Phone = u.Phone,
                IsTeacher = u.Role == "teacher",
                AvatarPath = u.AvatarPath,
                IsOnline = u.IsOnline
            };
        }).ToList();

        return Ok(result);
    }

    private Guid GetUserId() =>
        Guid.Parse(User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                   ?? User.FindFirst("sub")!.Value);
}
