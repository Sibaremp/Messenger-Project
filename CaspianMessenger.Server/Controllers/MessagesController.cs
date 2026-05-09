using System.Security.Claims;
using CaspianMessenger.Server.DTOs.Message;
using CaspianMessenger.Server.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/chats/{chatId:guid}")]
[Authorize]
public class MessagesController(MessageService messageService, ChatService chatService, NotificationService notificationService) : ControllerBase
{
    [HttpPost("messages")]
    public async Task<IActionResult> SendMessage(Guid chatId, [FromBody] SendMessageRequest req)
    {
        var userId = GetUserId();
        var (chat, error) = await messageService.SendMessageAsync(chatId, userId, req);
        if (error != null) return BadRequest(new { message = error });

        var memberIds = await chatService.GetChatMemberIdsAsync(chatId);
        var lastMsg = chat!.Messages.LastOrDefault();
        if (lastMsg != null)
            await notificationService.NotifyMessageReceived(memberIds, chatId, lastMsg);

        return Ok(chat);
    }

    [HttpPut("messages/{messageId:guid}")]
    public async Task<IActionResult> EditMessage(Guid chatId, Guid messageId, [FromBody] EditMessageRequest req)
    {
        var userId = GetUserId();
        var (chat, error) = await messageService.EditMessageAsync(chatId, messageId, userId, req);
        if (error == "Can only edit own messages") return Forbid();
        if (error != null) return NotFound(new { message = error });

        var memberIds = await chatService.GetChatMemberIdsAsync(chatId);
        await notificationService.NotifyMessageEdited(memberIds, chatId, messageId, req.Text);

        return Ok(chat);
    }

    [HttpDelete("messages")]
    public async Task<IActionResult> DeleteMessages(Guid chatId, [FromBody] DeleteMessagesRequest req)
    {
        var userId = GetUserId();
        var (chat, error) = await messageService.DeleteMessagesAsync(chatId, userId, req.Ids);
        if (error == "Forbidden: can only delete own messages or must be admin/creator") return Forbid();
        if (error != null) return BadRequest(new { message = error });

        var memberIds = await chatService.GetChatMemberIdsAsync(chatId);
        await notificationService.NotifyMessagesDeleted(memberIds, chatId, req.Ids);

        return Ok(chat);
    }

    [HttpPost("forward")]
    public async Task<IActionResult> ForwardMessages(Guid chatId, [FromBody] ForwardMessagesRequest req)
    {
        var userId = GetUserId();
        var (chat, error) = await messageService.ForwardMessagesAsync(chatId, userId, req.MessageIds);
        if (error != null) return BadRequest(new { message = error });
        return Ok(chat);
    }

    [HttpPost("messages/{messageId:guid}/pin")]
    public async Task<IActionResult> PinMessage(Guid chatId, Guid messageId)
    {
        var userId = GetUserId();
        var (chat, error) = await messageService.PinMessageAsync(chatId, messageId, userId);
        if (error == "Not a member" || error == "Message not found") return NotFound(new { message = error });
        if (error == "Only admin or creator can pin messages in group chats") return Forbid();
        if (error != null) return BadRequest(new { message = error });

        var memberIds = await chatService.GetChatMemberIdsAsync(chatId);
        foreach (var memberId in memberIds)
        {
            await notificationService.SendRawEventAsync(memberId, new
            {
                type = "message_pinned",
                chatId,
                messageId
            });
        }

        return Ok(chat);
    }

    [HttpPost("messages/{messageId:guid}/unpin")]
    public async Task<IActionResult> UnpinMessage(Guid chatId, Guid messageId)
    {
        var userId = GetUserId();
        var (chat, error) = await messageService.UnpinMessageAsync(chatId, messageId, userId);
        if (error == "Not a member" || error == "Message not found") return NotFound(new { message = error });
        if (error == "Only admin or creator can unpin messages in group chats") return Forbid();
        if (error != null) return BadRequest(new { message = error });

        var memberIds = await chatService.GetChatMemberIdsAsync(chatId);
        foreach (var memberId in memberIds)
        {
            await notificationService.SendRawEventAsync(memberId, new
            {
                type = "message_unpinned",
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
