namespace CaspianMessenger.Server.DTOs.Files;

public class FileUploadResponse
{
    public string Path { get; set; } = string.Empty;
    public string FileName { get; set; } = string.Empty;
    public long FileSize { get; set; }
    public string Type { get; set; } = string.Empty;
    public string MimeType { get; set; } = string.Empty;
    public string? ThumbnailPath { get; set; }  // только для video
    public int? DurationMs { get; set; }          // только для video
}
