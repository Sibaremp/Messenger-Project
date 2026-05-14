using System.Security.Claims;
using CaspianMessenger.Server.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CaspianMessenger.Server.Controllers;

/// <summary>
/// Handles X25519 Diffie-Hellman key exchange between client and server.
/// The client calls this endpoint once per connection to establish a shared
/// AES-256 encryption key for transport-level message confidentiality.
/// </summary>
[ApiController]
[Route("api")]
[Authorize]
public class KeyExchangeController(EncryptionService encryption) : ControllerBase
{
    /// <summary>
    /// POST /api/key-exchange
    ///
    /// Body:  { "clientPublicKey": "&lt;base64-encoded X25519 public key&gt;" }
    /// Reply: { "serverPublicKey": "&lt;base64-encoded X25519 public key&gt;" }
    ///
    /// After this call the server stores a derived AES-256 key for the authenticated
    /// user; the client should derive the same key from its private key + the returned
    /// server public key.
    /// </summary>
    [HttpPost("key-exchange")]
    public IActionResult Exchange([FromBody] KeyExchangeRequest req)
    {
        var userIdStr = User.FindFirstValue(ClaimTypes.NameIdentifier)
                     ?? User.FindFirstValue("sub");

        if (!Guid.TryParse(userIdStr, out var userId))
            return Unauthorized();

        var serverPublicKey = encryption.PerformKeyExchange(userId, req.ClientPublicKey);
        return Ok(new { serverPublicKey });
    }
}

/// <param name="ClientPublicKey">Base64-encoded 32-byte X25519 public key from the client.</param>
public record KeyExchangeRequest(string ClientPublicKey);
