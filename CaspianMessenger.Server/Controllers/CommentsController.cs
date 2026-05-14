using System.Security.Claims;
using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.DTOs.Comment;
using CaspianMessenger.Server.Models;
using CaspianMessenger.Server.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/chats/{chatId:guid}/messages/{messageId:guid}/comments")]
[Authorize]
public class CommentsController(AppDbContext db, ChatService chatService, ProfanityFilter profanity) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> AddComment(Guid chatId, Guid messageId, [FromBody] AddCommentRequest req)
    {
        var userId = GetUserId();
        var isMember = await db.ChatMembers.AnyAsync(cm => cm.ChatId == chatId && cm.UserId == userId);
        if (!isMember) return Forbid();

        var message = await db.Messages.FirstOrDefaultAsync(m => m.Id == messageId && m.ChatId == chatId);
        if (message == null) return NotFound();

        var comment = new Comment
        {
            MessageId = messageId,
            SenderId = userId,
            Text = profanity.Filter(req.Text),
            ReplyToId = req.ReplyTo?.CommentId
        };

        db.Comments.Add(comment);

        if (req.Attachment != null)
        {
            db.Attachments.Add(new Attachment
            {
                CommentId = comment.Id,
                FilePath = req.Attachment.Path,
                FileName = req.Attachment.FileName,
                FileSize = req.Attachment.FileSize,
                Type = req.Attachment.Type,
                MimeType = req.Attachment.MimeType,
                ThumbnailPath = req.Attachment.ThumbnailPath,
                DurationMs = req.Attachment.DurationMs
            });
        }

        await db.SaveChangesAsync();
        return Ok(await chatService.GetChatAsync(chatId, userId));
    }

    [HttpPut("{commentId:guid}")]
    public async Task<IActionResult> EditComment(Guid chatId, Guid messageId, Guid commentId, [FromBody] EditCommentRequest req)
    {
        var userId = GetUserId();
        var comment = await db.Comments.FirstOrDefaultAsync(c => c.Id == commentId && c.MessageId == messageId);
        if (comment == null) return NotFound();
        if (comment.SenderId != userId) return Forbid();

        comment.Text = profanity.Filter(req.Text);
        comment.IsEdited = true;

        await db.SaveChangesAsync();
        return Ok(await chatService.GetChatAsync(chatId, userId));
    }

    [HttpDelete]
    public async Task<IActionResult> DeleteComments(Guid chatId, Guid messageId, [FromBody] DeleteCommentsRequest req)
    {
        var userId = GetUserId();
        var member = await db.ChatMembers.FirstOrDefaultAsync(cm => cm.ChatId == chatId && cm.UserId == userId);
        if (member == null) return Forbid();

        var isAdminOrCreator = member.Role is "admin" or "creator";

        var comments = await db.Comments
            .Where(c => c.MessageId == messageId && req.Ids.Contains(c.Id))
            .ToListAsync();

        foreach (var comment in comments)
        {
            if (comment.SenderId != userId && !isAdminOrCreator)
                return Forbid();
            db.Comments.Remove(comment);
        }

        await db.SaveChangesAsync();
        return Ok(await chatService.GetChatAsync(chatId, userId));
    }

    private Guid GetUserId() =>
        Guid.Parse(User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                   ?? User.FindFirst("sub")!.Value);
}
