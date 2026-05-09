namespace CaspianMessenger.Server.Helpers;

public static class UserAgentParser
{
    public static (string DeviceName, string? Platform) Parse(string? userAgent)
    {
        if (string.IsNullOrWhiteSpace(userAgent))
            return ("Неизвестное устройство", null);

        var ua = userAgent.ToLowerInvariant();

        // Flutter/Dart HTTP client
        if (ua.Contains("android")) return ("Android устройство", "android");
        if (ua.Contains("iphone") || ua.Contains("ios")) return ("iOS устройство", "ios");

        // Desktop
        if (ua.Contains("windows"))
        {
            var browser = ua.Contains("chrome") ? "Chrome" : ua.Contains("firefox") ? "Firefox" : ua.Contains("edge") ? "Edge" : "Browser";
            return ($"{browser} · Windows", "windows");
        }
        if (ua.Contains("macintosh") || ua.Contains("mac os"))
        {
            var browser = ua.Contains("chrome") ? "Chrome" : ua.Contains("firefox") ? "Firefox" : ua.Contains("safari") ? "Safari" : "Browser";
            return ($"{browser} · macOS", "macos");
        }
        if (ua.Contains("linux"))
        {
            var browser = ua.Contains("chrome") ? "Chrome" : ua.Contains("firefox") ? "Firefox" : "Browser";
            return ($"{browser} · Linux", "linux");
        }

        // Web fallback
        if (ua.Contains("mozilla") || ua.Contains("chrome") || ua.Contains("safari"))
            return ("Веб-браузер", "web");

        return ("Неизвестное устройство", null);
    }
}
