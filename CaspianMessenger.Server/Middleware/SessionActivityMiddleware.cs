using System.Security.Claims;
using CaspianMessenger.Server.Helpers;
using CaspianMessenger.Server.Services;

namespace CaspianMessenger.Server.Middleware;

public class SessionActivityMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context, SessionService sessionService)
    {
        await next(context);

        // Update LastActivity for authenticated requests
        if (context.User.Identity?.IsAuthenticated == true)
        {
            var token = context.Request.Headers.Authorization.ToString().Replace("Bearer ", "");
            if (!string.IsNullOrEmpty(token))
            {
                var tokenHash = TokenHashHelper.ComputeSha256(token);
                await sessionService.UpdateLastActivityAsync(tokenHash);
            }
        }
    }
}
