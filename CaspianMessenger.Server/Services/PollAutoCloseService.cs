using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.Hubs;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Services;

public class PollAutoCloseService(IServiceScopeFactory scopeFactory, IHubContext<ChatHub> hubContext, ILogger<PollAutoCloseService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            await CloseExpiredPollsAsync();
            await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
        }
    }

    private async Task CloseExpiredPollsAsync()
    {
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var expiredPolls = await db.Polls
            .Where(p => !p.IsClosed && p.Deadline != null && p.Deadline <= DateTime.UtcNow)
            .ToListAsync();

        foreach (var poll in expiredPolls)
        {
            poll.IsClosed = true;
            logger.LogInformation("Auto-closing poll {PollId}", poll.Id);
        }

        if (expiredPolls.Count == 0) return;

        await db.SaveChangesAsync();

        // Notify via SignalR
        var pollIds = expiredPolls.Select(p => p.Id).ToList();
        var messages = await db.Messages
            .Where(m => m.PollId != null && pollIds.Contains(m.PollId!.Value))
            .Include(m => m.Chat).ThenInclude(c => c.Members)
            .ToListAsync();

        foreach (var msg in messages)
        {
            var memberIds = msg.Chat.Members.Select(m => m.UserId).ToList();
            foreach (var memberId in memberIds)
            {
                await hubContext.Clients.Group(memberId.ToString())
                    .SendAsync("ReceiveEvent", new
                    {
                        type = "poll_closed",
                        chatId = msg.ChatId,
                        messageId = msg.Id
                    });
            }
        }
    }
}
