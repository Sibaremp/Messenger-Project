namespace CaspianMessenger.Server.Models;

/// <summary>
/// Фабрика data-only FCM payload-ов.
/// FCM data-only messages не показывают системного уведомления —
/// приложение само решает, что показать.
/// </summary>
public static class NotificationPayload
{
    private const int MaxTextLength = 120;

    /// <summary>Новое сообщение в чате.</summary>
    public static Dictionary<string, string> Message(
        string chatId,
        string senderId,
        string senderName,
        string text,
        string avatarUrl = "",
        bool isGroup = false,
        string? chatName = null,
        string? attachmentType = null)
    {
        var payload = new Dictionary<string, string>
        {
            ["type"]       = "message",
            ["chatId"]     = chatId,
            ["senderId"]   = senderId,
            ["senderName"] = senderName,
            ["text"]       = text.Length > MaxTextLength ? text[..MaxTextLength] + "…" : text,
            ["avatarUrl"]  = avatarUrl,
            ["isGroup"]    = isGroup.ToString().ToLowerInvariant()
        };
        if (!string.IsNullOrEmpty(chatName))
            payload["chatName"] = chatName;
        if (!string.IsNullOrEmpty(attachmentType))
            payload["attachmentType"] = attachmentType;
        return payload;
    }

    /// <summary>Входящий звонок.</summary>
    public static Dictionary<string, string> Call(
        string callId,
        string callerId,
        string callerName,
        bool isVideo,
        bool isGroup = false) => new()
    {
        ["type"]       = "call_incoming",
        ["callId"]     = callId,
        ["callerId"]   = callerId,
        ["callerName"] = callerName,
        ["isVideo"]    = isVideo.ToString().ToLowerInvariant(),
        ["isGroup"]    = isGroup.ToString().ToLowerInvariant()
    };

    /// <summary>Системное событие (сессия завершена, упоминание и т.д.).</summary>
    public static Dictionary<string, string> System(
        string eventType,
        Dictionary<string, string>? extra = null)
    {
        var data = new Dictionary<string, string> { ["type"] = eventType };
        if (extra != null)
            foreach (var kv in extra)
                data[kv.Key] = kv.Value;
        return data;
    }
}
