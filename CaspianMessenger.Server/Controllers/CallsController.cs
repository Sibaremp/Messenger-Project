using CaspianMessenger.Server.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/calls")]
[Authorize]
public class CallsController(CallService callService) : ControllerBase
{
    /// <summary>Returns ICE server configuration for WebRTC clients.</summary>
    [HttpGet("ice-servers")]
    public IActionResult GetIceServers() =>
        Ok(new
        {
            iceServers = new[]
            {
                new { urls = "stun:stun.l.google.com:19302" },
                new { urls = "stun:stun1.l.google.com:19302" }
            }
        });

    /// <summary>
    /// Returns the active group call for a chat, or 404 if none.
    /// Used by clients to show a "Join call" banner when opening a chat.
    /// </summary>
    [HttpGet("active-for-chat/{chatId}")]
    public IActionResult GetActiveCallForChat(string chatId)
    {
        var call = callService.GetActiveChatCall(chatId);
        if (call == null) return NotFound();

        return Ok(new
        {
            callId         = call.Id.ToString(),
            callerId       = call.InitiatorId,
            callerName     = call.InitiatorName,
            isVideo        = call.Type == "video",
            isGroup        = call.IsGroup,
            participantCount = call.Participants.Count,
        });
    }
}
