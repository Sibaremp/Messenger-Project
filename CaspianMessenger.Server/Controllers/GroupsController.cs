using CaspianMessenger.Server.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/groups")]
public class GroupsController(AppDbContext db) : ControllerBase
{
    // Предустановленные группы колледжа (отображаются при регистрации)
    private static readonly List<string> DefaultGroups =
    [
        "ИС-21", "ИС-22", "ИС-23",
        "ПМ-21", "ПМ-22", "ПМ-23",
        "ЭК-21", "ЭК-22", "ЭК-23",
        "БУ-21", "БУ-22", "БУ-23",
        "ПР-21", "ПР-22", "ПР-23"
    ];

    [HttpGet]
    public async Task<IActionResult> GetGroups()
    {
        // Объединяем группы из БД с предустановленными
        var dbGroups = await db.Users
            .Where(u => u.Group != null)
            .Select(u => u.Group!)
            .Distinct()
            .ToListAsync();

        var all = DefaultGroups.Union(dbGroups).OrderBy(g => g).ToList();
        return Ok(all);
    }
}
