using System.Collections.Concurrent;
using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.Models;

namespace CaspianMessenger.Server.Services;

public class CallService(IServiceScopeFactory scopeFactory, ILogger<CallService> logger)
{
    // Singleton in-memory state: callId -> ActiveCall
    private static readonly ConcurrentDictionary<Guid, ActiveCall> _calls = new();

    public async Task<ActiveCall> CreateCallAsync(
        Guid callId, string initiatorId, string initiatorName,
        bool isVideo, bool isGroup, string? chatId = null)
    {
        var type = isVideo ? "video" : "audio";
        var call = new ActiveCall
        {
            Id = callId,
            Type = type,
            State = "calling",
            IsGroup = isGroup,
            InitiatorId = initiatorId,
            InitiatorName = initiatorName,
            ChatId = chatId,
            Participants = [initiatorId]
        };
        _calls[callId] = call;

        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        db.Calls.Add(new Call { Id = callId, Type = type, State = "calling" });
        db.CallParticipants.Add(new CallParticipant { CallId = callId, UserId = initiatorId });
        await db.SaveChangesAsync();

        logger.LogInformation("Call {CallId} created by {UserId}", callId, initiatorId);
        return call;
    }

    public async Task<bool> JoinCallAsync(Guid callId, string userId)
    {
        if (!_calls.TryGetValue(callId, out var call)) return false;

        lock (call.Participants)
        {
            call.Participants.Add(userId);
            call.State = "active";
        }

        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var dbCall = await db.Calls.FindAsync(callId);
        if (dbCall != null) dbCall.State = "active";
        db.CallParticipants.Add(new CallParticipant { CallId = callId, UserId = userId });
        await db.SaveChangesAsync();

        return true;
    }

    public async Task<(bool callEnded, IReadOnlyCollection<string> remaining)> LeaveCallAsync(Guid callId, string userId)
    {
        if (!_calls.TryGetValue(callId, out var call))
            return (false, []);

        bool ended;
        List<string> remaining;
        lock (call.Participants)
        {
            call.Participants.Remove(userId);
            // Call ends when no participants remain, or when the initiator leaves
            ended = call.Participants.Count == 0 || call.InitiatorId == userId;
            remaining = [.. call.Participants];
        }

        if (ended)
        {
            _calls.TryRemove(callId, out _);
            using var scope = scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var dbCall = await db.Calls.FindAsync(callId);
            if (dbCall != null)
            {
                dbCall.State = "ended";
                await db.SaveChangesAsync();
            }
            logger.LogInformation("Call {CallId} ended", callId);
        }

        return (ended, remaining);
    }

    public ActiveCall? GetCall(Guid callId) => _calls.GetValueOrDefault(callId);

    public ActiveCall? GetActiveChatCall(string chatId) =>
        _calls.Values.FirstOrDefault(c => c.ChatId == chatId && c.State != "ended");

    public IEnumerable<ActiveCall> GetUserActiveCalls(string userId) =>
        _calls.Values.Where(c => c.Participants.Contains(userId));
}
