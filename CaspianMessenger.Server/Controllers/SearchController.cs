using System.Security.Claims;
using CaspianMessenger.Server.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CaspianMessenger.Server.Controllers;

[ApiController]
[Route("api/messages")]
[Authorize]
public class SearchController(MessageService messageService) : ControllerBase
{
    [HttpGet("search")]
    public async Task<IActionResult> SearchMessages([FromQuery] string q)
    {
        var results = await messageService.SearchMessagesAsync(GetUserId(), q);
        return Ok(results);
    }

    private Guid GetUserId() =>
        Guid.Parse(User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                   ?? User.FindFirst("sub")!.Value);
}
