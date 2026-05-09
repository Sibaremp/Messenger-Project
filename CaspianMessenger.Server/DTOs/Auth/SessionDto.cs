namespace CaspianMessenger.Server.DTOs.Auth;

public class SessionDto
{
    public Guid SessionId { get; set; }
    public string DeviceName { get; set; } = string.Empty;
    public string? Platform { get; set; }
    public string? Location { get; set; }
    public DateTime LastActivity { get; set; }
    public bool IsCurrent { get; set; }
}
