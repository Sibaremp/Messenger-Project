using CaspianMessenger.Server.DTOs.Message;

namespace CaspianMessenger.Server.DTOs.Comment;

public class AddCommentRequest
{
    public string Text { get; set; } = string.Empty;
    public AttachmentRequest? Attachment { get; set; }
    public CommentReplyRequest? ReplyTo { get; set; }
}

public class CommentReplyRequest
{
    public Guid CommentId { get; set; }
    public string SenderName { get; set; } = string.Empty;
    public string Text { get; set; } = string.Empty;
}
