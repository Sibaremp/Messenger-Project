using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.DTOs.Chat;
using CaspianMessenger.Server.DTOs.Polls;
using CaspianMessenger.Server.Models;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Services;

public class PollService(AppDbContext db, ChatService chatService)
{
    public async Task<(ChatDto? Chat, string? Error)> CreatePollAsync(Guid chatId, Guid senderId, CreatePollRequest req)
    {
        // Validate
        var chat = await db.Chats.FindAsync(chatId);
        if (chat == null) return (null, "Chat not found");
        if (chat.Type == "direct") return (null, "Polls are not allowed in direct chats");

        var isMember = await db.ChatMembers.AnyAsync(cm => cm.ChatId == chatId && cm.UserId == senderId);
        if (!isMember) return (null, "Not a member");

        if (req.Options.Count < 2 || req.Options.Count > 10)
            return (null, "Poll must have 2–10 options");
        if (req.Question.Length > 500)
            return (null, "Question too long (max 500 chars)");
        if (req.Deadline.HasValue && req.Deadline.Value <= DateTime.UtcNow)
            return (null, "Deadline must be in the future");

        // Create poll
        var poll = new Poll
        {
            Question = req.Question,
            Type = req.Type,
            IsAnonymous = req.IsAnonymous,
            CanChangeVote = req.CanChangeVote,
            Deadline = req.Deadline
        };
        db.Polls.Add(poll);

        for (int i = 0; i < req.Options.Count; i++)
            db.PollOptions.Add(new PollOption { PollId = poll.Id, Text = req.Options[i], Position = i });

        // Create message with poll
        var message = new Message
        {
            ChatId = chatId,
            SenderId = senderId,
            Text = string.Empty,
            PollId = poll.Id,
            Status = "sent"
        };
        db.Messages.Add(message);

        await db.SaveChangesAsync();
        return (await chatService.GetChatAsync(chatId, senderId), null);
    }

    public async Task<(ChatDto? Chat, string? Error)> VoteAsync(Guid chatId, Guid messageId, Guid userId, VotePollRequest req)
    {
        var message = await db.Messages
            .Include(m => m.Poll).ThenInclude(p => p!.Options)
            .Include(m => m.Poll).ThenInclude(p => p!.Votes)
            .FirstOrDefaultAsync(m => m.Id == messageId && m.ChatId == chatId);

        if (message?.Poll == null) return (null, "Poll not found");
        var poll = message.Poll;

        if (poll.IsClosed) return (null, "Poll is closed");
        if (poll.Deadline.HasValue && poll.Deadline.Value <= DateTime.UtcNow)
            return (null, "Poll deadline has passed");

        var isMember = await db.ChatMembers.AnyAsync(cm => cm.ChatId == chatId && cm.UserId == userId);
        if (!isMember) return (null, "Not a member");

        var validOptionIds = poll.Options.Select(o => o.Id).ToHashSet();
        if (!req.OptionIds.All(id => validOptionIds.Contains(id)))
            return (null, "Invalid option id");

        if (poll.Type == "single" && req.OptionIds.Count != 1)
            return (null, "Single-choice poll requires exactly 1 option");
        if (poll.Type == "multiple" && (req.OptionIds.Count < 1 || req.OptionIds.Count > poll.Options.Count))
            return (null, "Invalid number of options");

        var existingVotes = poll.Votes.Where(v => v.UserId == userId).ToList();
        if (existingVotes.Count > 0 && !poll.CanChangeVote)
            return (null, "Vote cannot be changed");

        // Remove existing votes and add new
        db.PollVotes.RemoveRange(existingVotes);
        foreach (var optId in req.OptionIds)
            db.PollVotes.Add(new PollVote { PollId = poll.Id, OptionId = optId, UserId = userId });

        await db.SaveChangesAsync();
        return (await chatService.GetChatAsync(chatId, userId), null);
    }

    public async Task<(ChatDto? Chat, string? Error)> CloseAsync(Guid chatId, Guid messageId, Guid userId)
    {
        var member = await db.ChatMembers.FirstOrDefaultAsync(cm => cm.ChatId == chatId && cm.UserId == userId);
        if (member == null || (member.Role != "creator" && member.Role != "admin"))
            return (null, "Only admin or creator can close the poll");

        var message = await db.Messages.Include(m => m.Poll).FirstOrDefaultAsync(m => m.Id == messageId && m.ChatId == chatId);
        if (message?.Poll == null) return (null, "Poll not found");
        if (message.Poll.IsClosed) return (null, "Poll is already closed");

        message.Poll.IsClosed = true;
        await db.SaveChangesAsync();
        return (await chatService.GetChatAsync(chatId, userId), null);
    }

    public static PollDto MapPollToDto(Poll poll, Guid currentUserId)
    {
        var optionVoteCounts = poll.Votes
            .GroupBy(v => v.OptionId)
            .ToDictionary(g => g.Key, g => g.Count());

        var myVotes = poll.Votes
            .Where(v => v.UserId == currentUserId)
            .Select(v => v.OptionId)
            .ToList();

        Dictionary<string, List<Guid>> userVotes = [];
        if (!poll.IsAnonymous)
        {
            userVotes = poll.Votes
                .GroupBy(v => v.UserId.ToString())
                .ToDictionary(
                    g => g.Key,
                    g => g.Select(v => v.OptionId).ToList()
                );
        }

        return new PollDto
        {
            Id = poll.Id,
            Question = poll.Question,
            Type = poll.Type,
            IsAnonymous = poll.IsAnonymous,
            CanChangeVote = poll.CanChangeVote,
            Deadline = poll.Deadline,
            IsClosed = poll.IsClosed,
            MyVotes = myVotes,
            UserVotes = userVotes,
            Options = poll.Options.OrderBy(o => o.Position).Select(o => new PollOptionDto
            {
                Id = o.Id,
                Text = o.Text,
                Votes = optionVoteCounts.GetValueOrDefault(o.Id, 0)
            }).ToList()
        };
    }
}
