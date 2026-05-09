using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/calls")]
[Authorize]
public class CallsController : ControllerBase
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
}
