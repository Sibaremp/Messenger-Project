using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.DTOs.Auth;
using CaspianMessenger.Server.Helpers;
using CaspianMessenger.Server.Hubs;
using CaspianMessenger.Server.Models;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;

namespace CaspianMessenger.Server.Services;

public class SessionService(
    AppDbContext db,
    IHubContext<ChatHub> hubContext,
    IMemoryCache cache)
{
    public async Task<Session> CreateSessionAsync(Guid userId, string token, string? userAgent, string? ipAddress)
    {
        var tokenHash = TokenHashHelper.ComputeSha256(token);
        var (deviceName, platform) = UserAgentParser.Parse(userAgent);

        var session = new Session
        {
            UserId = userId,
            TokenHash = tokenHash,
            DeviceName = deviceName,
            Platform = platform,
            Location = null // IP geolocation not implemented, leave null
        };

        db.Sessions.Add(session);
        await db.SaveChangesAsync();
        return session;
    }

    public async Task<List<SessionDto>> GetUserSessionsAsync(Guid userId, string currentToken)
    {
        var currentHash = TokenHashHelper.ComputeSha256(currentToken);
        var sessions = await db.Sessions
            .Where(s => s.UserId == userId && s.IsActive)
            .OrderByDescending(s => s.TokenHash == currentHash)
            .ThenByDescending(s => s.LastActivity)
            .ToListAsync();

        return sessions.Select(s => new SessionDto
        {
            SessionId = s.Id,
            DeviceName = s.DeviceName,
            Platform = s.Platform,
            Location = s.Location,
            LastActivity = s.LastActivity,
            IsCurrent = s.TokenHash == currentHash
        }).ToList();
    }

    public async Task<(bool Success, string? Error)> TerminateSessionAsync(Guid sessionId, Guid requesterId, string currentToken)
    {
        var session = await db.Sessions.FirstOrDefaultAsync(s => s.Id == sessionId && s.IsActive);
        if (session == null) return (false, "Session not found");
        if (session.UserId != requesterId) return (false, "Forbidden");

        session.IsActive = false;
        await db.SaveChangesAsync();

        var currentHash = TokenHashHelper.ComputeSha256(currentToken);

        // Notify the terminated session (isCurrent: true)
        await hubContext.Clients
            .Group($"session_{session.TokenHash}")
            .SendAsync("ReceiveEvent", new
            {
                type = "session_terminated",
                sessionId = session.Id,
                isCurrent = true
            });

        // Notify other sessions of the same user (isCurrent: false)
        await hubContext.Clients
            .Group($"user_{requesterId}")
            .SendAsync("ReceiveEvent", new
            {
                type = "session_terminated",
                sessionId = session.Id,
                isCurrent = false
            });

        return (true, null);
    }

    public async Task TerminateAllSessionsAsync(Guid userId, string currentToken)
    {
        var sessions = await db.Sessions
            .Where(s => s.UserId == userId && s.IsActive)
            .ToListAsync();

        var currentHash = TokenHashHelper.ComputeSha256(currentToken);

        foreach (var s in sessions)
            s.IsActive = false;

        await db.SaveChangesAsync();

        // Notify each session
        foreach (var s in sessions)
        {
            await hubContext.Clients
                .Group($"session_{s.TokenHash}")
                .SendAsync("ReceiveEvent", new
                {
                    type = "session_terminated",
                    sessionId = s.Id,
                    isCurrent = s.TokenHash == currentHash
                });
        }
    }

    /// Throttled LastActivity update: max once per 5 minutes per session
    public async Task UpdateLastActivityAsync(string tokenHash)
    {
        var cacheKey = $"activity_{tokenHash}";
        if (cache.TryGetValue(cacheKey, out _)) return;

        cache.Set(cacheKey, true, TimeSpan.FromMinutes(5));

        var session = await db.Sessions.FirstOrDefaultAsync(s => s.TokenHash == tokenHash && s.IsActive);
        if (session != null)
        {
            session.LastActivity = DateTime.UtcNow;
            await db.SaveChangesAsync();
        }
    }

    public async Task<bool> IsSessionActiveAsync(string tokenHash)
    {
        return await db.Sessions.AnyAsync(s => s.TokenHash == tokenHash && s.IsActive);
    }
}
