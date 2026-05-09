using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.Helpers;
using CaspianMessenger.Server.Hubs;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Services;

public class SessionCleanupService(IServiceScopeFactory scopeFactory, IHubContext<ChatHub> hubContext, ILogger<SessionCleanupService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromHours(6));
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            await CleanupExpiredSessionsAsync();
        }
    }

    private async Task CleanupExpiredSessionsAsync()
    {
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var cutoff = DateTime.UtcNow.AddDays(-30);

        var expired = await db.Sessions
            .Where(s => s.IsActive && s.LastActivity < cutoff)
            .ToListAsync();

        foreach (var s in expired)
            s.IsActive = false;

        if (expired.Count > 0)
        {
            await db.SaveChangesAsync();
            logger.LogInformation("Expired {Count} sessions", expired.Count);

            foreach (var s in expired)
            {
                await hubContext.Clients
                    .Group($"session_{s.TokenHash}")
                    .SendAsync("ReceiveEvent", new
                    {
                        type = "session_terminated",
                        sessionId = s.Id,
                        isCurrent = true
                    });
            }
        }
    }
}
