using System.Security.Claims;
using CaspianMessenger.Server.DTOs.Polls;
using CaspianMessenger.Server.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/chats/{chatId:guid}/polls")]
[Authorize]
public class PollsController(PollService pollService, ChatService chatService, NotificationService notificationService) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> CreatePoll(Guid chatId, [FromBody] CreatePollRequest req)
    {
        var userId = GetUserId();
        var (chat, error) = await pollService.CreatePollAsync(chatId, userId, req);
        if (error != null) return BadRequest(new { message = error });

        var memberIds = await chatService.GetChatMemberIdsAsync(chatId);
        var lastMsg = chat!.Messages.LastOrDefault();
        if (lastMsg != null)
            await notificationService.NotifyMessageReceived(memberIds, chatId, lastMsg);

        return Ok(chat);
    }

    [HttpPost("{messageId:guid}/vote")]
    public async Task<IActionResult> Vote(Guid chatId, Guid messageId, [FromBody] VotePollRequest req)
    {
        var userId = GetUserId();
        var (chat, error) = await pollService.VoteAsync(chatId, messageId, userId, req);
        if (error == "Not a member" || error == "Poll not found") return NotFound(new { message = error });
        if (error != null) return BadRequest(new { message = error });

        // Notify other members about vote
        var memberIds = await chatService.GetChatMemberIdsAsync(chatId);
        var otherMembers = memberIds.Where(id => id != userId).ToList();
        foreach (var memberId in otherMembers)
        {
            await notificationService.SendRawEventAsync(memberId, new
            {
                type = "poll_voted",
                chatId,
                messageId,
                userId,
                optionIds = req.OptionIds
            });
        }

        return Ok(chat);
    }

    [HttpPost("{messageId:guid}/close")]
    public async Task<IActionResult> ClosePoll(Guid chatId, Guid messageId)
    {
        var userId = GetUserId();
        var (chat, error) = await pollService.CloseAsync(chatId, messageId, userId);
        if (error == "Only admin or creator can close the poll") return Forbid();
        if (error != null) return BadRequest(new { message = error });

        var memberIds = await chatService.GetChatMemberIdsAsync(chatId);
        foreach (var memberId in memberIds)
        {
            await notificationService.SendRawEventAsync(memberId, new
            {
                type = "poll_closed",
                chatId,
                messageId
            });
        }

        return Ok(chat);
    }

    private Guid GetUserId() =>
        Guid.Parse(User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                   ?? User.FindFirst("sub")!.Value);
}
