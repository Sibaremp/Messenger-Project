using CaspianMessenger.Server.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Controllers;

/// <summary>
/// Статистические эндпоинты для панели администратора.
/// Все данные возвращаются в UTC; фронтенд форматирует под локальную зону.
/// </summary>
[ApiController]
[Route("api/admin/stats")]
[Authorize(Policy = "AdminOnly")]
public class AdminStatsController(AppDbContext db) : ControllerBase
{
    // ── 1. Активность пользователей ───────────────────────────────────────────
    // GET /api/admin/stats/activity?days=14
    // Возвращает количество созданных сессий (= входов) по дням за последние N дней.

    [HttpGet("activity")]
    public async Task<IActionResult> GetActivity([FromQuery] int days = 14)
    {
        days = Math.Clamp(days, 1, 90);
        var since = DateTime.UtcNow.Date.AddDays(-days + 1);

        // Кол-во новых сессий по дням (вход в систему)
        var logins = await db.Sessions
            .Where(s => s.CreatedAt >= since)
            .GroupBy(s => s.CreatedAt.Date)
            .Select(g => new { date = g.Key, count = g.Count() })
            .ToListAsync();

        // Строим полный диапазон дней, заполняя нулями отсутствующие
        var result = Enumerable.Range(0, days)
            .Select(i =>
            {
                var d = since.AddDays(i);
                var entry = logins.FirstOrDefault(x => x.date == d);
                return new
                {
                    date   = d.ToString("yyyy-MM-dd"),
                    logins = entry?.count ?? 0
                };
            })
            .ToList();

        return Ok(result);
    }

    // ── 2. Уведомления по неделям ─────────────────────────────────────────────
    // GET /api/admin/stats/notifications?weeks=8
    // Возвращает кол-во отправленных уведомлений и охват устройств по неделям.

    [HttpGet("notifications")]
    public async Task<IActionResult> GetNotificationStats([FromQuery] int weeks = 8)
    {
        weeks = Math.Clamp(weeks, 1, 52);

        // Первый день текущей недели (понедельник)
        var today = DateTime.UtcNow.Date;
        var dayOfWeek = (int)today.DayOfWeek;
        var weekStart = today.AddDays(-(dayOfWeek == 0 ? 6 : dayOfWeek - 1));

        var since = weekStart.AddDays(-7 * (weeks - 1));

        var notifications = await db.Notifications
            .Where(n => n.SentAt >= since)
            .Select(n => new { n.SentAt, n.SentCount })
            .ToListAsync();

        var result = Enumerable.Range(0, weeks)
            .Select(i =>
            {
                var ws = since.AddDays(i * 7);
                var we = ws.AddDays(6);
                var entries = notifications
                    .Where(n => n.SentAt.Date >= ws && n.SentAt.Date <= we)
                    .ToList();

                var label = ws.Month == we.Month
                    ? $"{ws.Day}–{we.Day} {MonthShort(ws.Month)}"
                    : $"{ws.Day} {MonthShort(ws.Month)} – {we.Day} {MonthShort(we.Month)}";

                return new
                {
                    weekStart = ws.ToString("yyyy-MM-dd"),
                    label,
                    count   = entries.Count,
                    devices = entries.Sum(x => x.SentCount)
                };
            })
            .ToList();

        return Ok(result);
    }

    // ── 3. Прирост участников ─────────────────────────────────────────────────
    // GET /api/admin/stats/growth?days=30
    // Возвращает кол-во новых участников по дням и нарастающий итог.

    [HttpGet("growth")]
    public async Task<IActionResult> GetGrowth([FromQuery] int days = 30)
    {
        days = Math.Clamp(days, 1, 365);
        var since = DateTime.UtcNow.Date.AddDays(-days + 1);

        // Всего участников до начала периода (нарастающий старт)
        var baseCount = await db.People
            .CountAsync(p => p.CreatedAt < since);

        // Новые по дням внутри периода
        var byDay = await db.People
            .Where(p => p.CreatedAt >= since)
            .GroupBy(p => p.CreatedAt.Date)
            .Select(g => new { date = g.Key, newCount = g.Count() })
            .ToListAsync();

        // Зарегистрированные аккаунты мессенджера по дням
        var baseUsers = await db.Users.CountAsync(u => u.CreatedAt < since);
        var usersByDay = await db.Users
            .Where(u => u.CreatedAt >= since)
            .GroupBy(u => u.CreatedAt.Date)
            .Select(g => new { date = g.Key, newCount = g.Count() })
            .ToListAsync();

        var cumulativePeople = baseCount;
        var cumulativeUsers  = baseUsers;
        var result = Enumerable.Range(0, days)
            .Select(i =>
            {
                var d        = since.AddDays(i);
                var pEntry   = byDay.FirstOrDefault(x => x.date == d);
                var uEntry   = usersByDay.FirstOrDefault(x => x.date == d);
                var newPeople = pEntry?.newCount ?? 0;
                var newUsers  = uEntry?.newCount ?? 0;
                cumulativePeople += newPeople;
                cumulativeUsers  += newUsers;
                return new
                {
                    date            = d.ToString("yyyy-MM-dd"),
                    newCount        = newPeople,
                    total           = cumulativePeople,
                    newRegistered   = newUsers,
                    totalRegistered = cumulativeUsers
                };
            })
            .ToList();

        return Ok(result);
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    private static string MonthShort(int month) => month switch
    {
        1  => "янв", 2  => "фев", 3  => "мар", 4  => "апр",
        5  => "май", 6  => "июн", 7  => "июл", 8  => "авг",
        9  => "сен", 10 => "окт", 11 => "ноя", 12 => "дек",
        _  => ""
    };
}
