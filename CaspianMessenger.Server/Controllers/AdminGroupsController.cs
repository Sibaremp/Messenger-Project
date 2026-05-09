using CaspianMessenger.Server.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/admin")]
[Authorize(Policy = "AdminOnly")]
public class AdminGroupsController(
    AppDbContext db,
    ILogger<AdminGroupsController> logger) : ControllerBase
{
    // ── GROUPS ────────────────────────────────────────────────────────────────

    /// GET /api/admin/groups
    /// Returns all distinct groups with statistics.
    [HttpGet("groups")]
    public async Task<IActionResult> GetGroups()
    {
        // All distinct group values from People table
        var groups = await db.People
            .Where(p => p.Group != null)
            .GroupBy(p => p.Group!)
            .Select(g => new
            {
                name        = g.Key,
                peopleCount = g.Count(),
                userCount   = g.Count(p => p.UserId != null)
            })
            .OrderBy(g => g.name)
            .ToListAsync();

        return Ok(groups);
    }

    /// DELETE /api/admin/groups/{name}
    /// Cascade: dissolve academic chat → invalidate sessions → delete users → clear group on people.
    [HttpDelete("groups/{name}")]
    public async Task<IActionResult> DeleteGroup(string name)
    {
        // Check group exists
        var anyPerson = await db.People.AnyAsync(p => p.Group == name);
        var anyUser   = await db.Users.AnyAsync(u => u.Group == name);
        if (!anyPerson && !anyUser)
            return NotFound(new { message = "Группа не найдена" });

        // 1. Find the academic chat for this group and remove it (cascades members/messages)
        var chat = await db.Chats
            .FirstOrDefaultAsync(c => c.IsAcademic && c.Name == name);
        if (chat != null)
        {
            db.Chats.Remove(chat);
            logger.LogInformation("Removing academic chat for group '{Group}'", name);
        }

        // 2. Invalidate sessions of users in this group
        var userIds = await db.Users
            .Where(u => u.Group == name)
            .Select(u => u.Id)
            .ToListAsync();

        if (userIds.Count > 0)
        {
            var sessions = await db.Sessions
                .Where(s => userIds.Contains(s.UserId) && s.IsActive)
                .ToListAsync();
            foreach (var s in sessions)
                s.IsActive = false;

            // 3. Remove FCM devices for those users
            var devices = await db.UserDevices
                .Where(d => userIds.Contains(d.UserId))
                .ToListAsync();
            db.UserDevices.RemoveRange(devices);

            // 4. Delete the users themselves
            var users = await db.Users
                .Where(u => u.Group == name)
                .ToListAsync();
            db.Users.RemoveRange(users);

            logger.LogInformation(
                "Deleting {Count} users and {SessionCount} sessions for group '{Group}'",
                users.Count, sessions.Count, name);
        }

        // 5. Clear Group on all People in this group (keep people, just unassign)
        var people = await db.People
            .Where(p => p.Group == name)
            .ToListAsync();
        foreach (var p in people)
            p.Group = null;

        logger.LogInformation("Cleared group '{Group}' from {Count} people", name, people.Count);

        await db.SaveChangesAsync();

        return Ok(new
        {
            message     = $"Группа '{name}' удалена",
            usersDeleted  = userIds.Count,
            peopleUpdated = people.Count
        });
    }
}
