using System.Security.Claims;
using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.DTOs.Chat;
using CaspianMessenger.Server.DTOs.Members;
using CaspianMessenger.Server.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;


namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/chats")]
[Authorize]
public class ChatsController(
    ChatService chatService,
    MessageService messageService,
    FileService fileService,
    AppDbContext db,
    EncryptionService encryption) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetChats()
    {
        var userId = GetUserId();
        var chats  = await chatService.GetUserChatsAsync(userId);
        encryption.EncryptChatsInPlace(chats, userId);
        return Ok(chats);
    }

    [HttpGet("{chatId:guid}")]
    public async Task<IActionResult> GetChat(Guid chatId, [FromQuery] int offset = 0, [FromQuery] int limit = 50)
    {
        var userId = GetUserId();
        var chat   = await chatService.GetChatAsync(chatId, userId, offset, limit);
        if (chat == null) return NotFound();
        encryption.EncryptChatInPlace(chat, userId);
        return Ok(chat);
    }

    [HttpPost("direct")]
    public async Task<IActionResult> CreateDirectChat([FromBody] CreateDirectChatRequest req)
    {
        var userId = GetUserId();
        var (chat, error) = await chatService.CreateDirectChatAsync(userId, req);
        if (error != null) return BadRequest(new { message = error });
        encryption.EncryptChatInPlace(chat!, userId);
        return Ok(chat);
    }

    [HttpPost("group")]
    public async Task<IActionResult> CreateGroupChat([FromBody] CreateGroupRequest req)
    {
        var userId = GetUserId();
        var (chat, error) = await chatService.CreateGroupChatAsync(userId, req);
        if (error != null) return BadRequest(new { message = error });
        encryption.EncryptChatInPlace(chat!, userId);
        return Ok(chat);
    }

    [HttpPut("{chatId:guid}/settings")]
    public async Task<IActionResult> UpdateSettings(Guid chatId, [FromBody] UpdateChatSettingsRequest req)
    {
        var userId = GetUserId();
        var (chat, error) = await chatService.UpdateChatSettingsAsync(chatId, userId, req);
        if (error == "Forbidden") return Forbid();
        if (error != null) return NotFound(new { message = error });
        encryption.EncryptChatInPlace(chat!, userId);
        return Ok(chat);
    }

    [HttpDelete("{chatId:guid}")]
    public async Task<IActionResult> DeleteChat(Guid chatId)
    {
        var (success, error) = await chatService.DeleteChatAsync(chatId, GetUserId());
        if (!success && error == "Only creator can delete the chat") return Forbid();
        if (!success) return NotFound(new { message = error });
        return NoContent();
    }

    [HttpPost("{chatId:guid}/members")]
    public async Task<IActionResult> AddMember(Guid chatId, [FromBody] AddMemberRequest req)
    {
        var requesterId = GetUserId();
        var (chat, error) = await chatService.AddMemberAsync(chatId, requesterId, req.UserId, req.Role);
        if (error == "Forbidden") return Forbid();
        if (error != null) return BadRequest(new { message = error });
        encryption.EncryptChatInPlace(chat!, requesterId);
        return Ok(chat);
    }

    /// <summary>Текущий пользователь вступает в группу по приглашению (self-join).</summary>
    [HttpPost("{chatId:guid}/join")]
    public async Task<IActionResult> JoinChat(Guid chatId)
    {
        var userId = GetUserId();
        var (chat, error) = await chatService.JoinChatAsync(chatId, userId);
        if (error == "Already a member") return Conflict(new { message = error });
        if (error != null) return BadRequest(new { message = error });
        encryption.EncryptChatInPlace(chat!, userId);
        return Ok(chat);
    }

    [HttpPut("{chatId:guid}/members/{userId:guid}")]
    public async Task<IActionResult> UpdateMemberRole(Guid chatId, Guid userId, [FromBody] UpdateMemberRoleRequest req)
    {
        var requesterId = GetUserId();
        var (chat, error) = await chatService.UpdateMemberRoleAsync(chatId, requesterId, userId, req.Role);
        if (error == "Only creator can change roles") return Forbid();
        if (error != null) return NotFound(new { message = error });
        encryption.EncryptChatInPlace(chat!, requesterId);
        return Ok(chat);
    }

    [HttpDelete("{chatId:guid}/members/{userId:guid}")]
    public async Task<IActionResult> RemoveMember(Guid chatId, Guid userId)
    {
        var requesterId = GetUserId();
        var (chat, error) = await chatService.RemoveMemberAsync(chatId, requesterId, userId);
        if (error == "Forbidden") return Forbid();
        if (error != null) return NotFound(new { message = error });
        encryption.EncryptChatInPlace(chat!, requesterId);
        return Ok(chat);
    }

    [HttpGet("search")]
    public async Task<IActionResult> SearchChats([FromQuery] string q)
    {
        var userId  = GetUserId();
        var results = await chatService.SearchChatsAsync(userId, q);
        encryption.EncryptChatsInPlace(results, userId);
        return Ok(results);
    }

    /// <summary>
    /// Uploads a new avatar image for the chat.
    /// Only admin or creator may change the avatar.
    /// Returns { avatarUrl, avatarPath, path } — all three point to the same server URL.
    /// </summary>
    [HttpPost("{chatId:guid}/avatar")]
    [RequestSizeLimit(10_485_760)] // 10 MB
    public async Task<IActionResult> UploadChatAvatar(Guid chatId, IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { message = "Файл не передан" });

        var userId = GetUserId();

        var member = await db.ChatMembers
            .FirstOrDefaultAsync(cm => cm.ChatId == chatId && cm.UserId == userId);
        if (member == null)
            return Forbid();
        if (member.Role != "creator" && member.Role != "admin")
            return Forbid();

        var chat = await db.Chats.FindAsync(chatId);
        if (chat == null) return NotFound(new { message = "Chat not found" });

        var (response, error) = await fileService.UploadFileAsync(file);
        if (error != null) return BadRequest(new { message = error });

        chat.AvatarPath = response!.Path;
        await db.SaveChangesAsync();

        return Ok(new
        {
            avatarUrl  = chat.AvatarPath,
            avatarPath = chat.AvatarPath,
            path       = chat.AvatarPath
        });
    }

    /// <summary>
    /// Marks all messages in a chat as read for the current user.
    /// Call this when the user opens a chat to reset the unread badge.
    /// </summary>
    [HttpPost("{chatId:guid}/read")]
    public async Task<IActionResult> MarkChatAsRead(Guid chatId)
    {
        var error = await messageService.MarkAllMessagesReadAsync(chatId, GetUserId());
        if (error == "Not a member") return Forbid();
        if (error != null) return BadRequest(new { message = error });
        return NoContent();
    }

    private Guid GetUserId() =>
        Guid.Parse(User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                   ?? User.FindFirst("sub")!.Value);
}
