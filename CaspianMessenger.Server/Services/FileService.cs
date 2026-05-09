using System.Diagnostics;
using System.Text.Json;
using CaspianMessenger.Server.DTOs.Files;

namespace CaspianMessenger.Server.Services;

public class FileService(IConfiguration config, IWebHostEnvironment env, ILogger<FileService> logger)
{
    private readonly string _basePath = config["FileStorage:BasePath"] ?? "./uploads";
    private readonly long _maxFileSizeBytes = (long)(double.Parse(config["FileStorage:MaxFileSizeMB"] ?? "50") * 1024 * 1024);
    private readonly string[] _allowedExtensions = (config["FileStorage:AllowedExtensions"] ?? ".jpg,.jpeg,.png,.gif,.mp4,.mov,.pdf,.doc,.docx,.xls,.xlsx").Split(',');
    private readonly string _ffmpegPath  = config["FFmpeg:FfmpegPath"]  ?? "ffmpeg";
    private readonly string _ffprobePath = config["FFmpeg:FfprobePath"] ?? "ffprobe";

    private static readonly string[] AudioMimeTypes =
    [
        "audio/mp4", "audio/m4a", "audio/x-m4a",
        "audio/mpeg", "audio/mp3",
        "audio/aac", "audio/x-aac",
        "audio/ogg", "audio/wav", "audio/wave",
        "audio/webm"
    ];

    private static readonly string[] AudioExtensions =
        [".m4a", ".mp3", ".aac", ".ogg", ".wav", ".webm", ".opus"];

    private const long MaxAudioBytes = 10L * 1024 * 1024; // 10 MB

    /// <summary>Загружает голосовое / аудио сообщение; возвращает публичный URL.</summary>
    public async Task<(string? Url, string? Error)> UploadAudioAsync(IFormFile file)
    {
        if (file.Length == 0)
            return (null, "Файл пустой");

        if (file.Length > MaxAudioBytes)
            return (null, "Размер файла превышает 10 МБ");

        var mime = file.ContentType?.ToLowerInvariant() ?? string.Empty;
        var ext  = Path.GetExtension(file.FileName).ToLowerInvariant();

        if (!AudioMimeTypes.Contains(mime) && !AudioExtensions.Contains(ext))
            return (null, $"Недопустимый тип файла: {mime}");

        // Нормализуем расширение: если mime известен — берём из него
        if (string.IsNullOrEmpty(ext) || !AudioExtensions.Contains(ext))
            ext = mime.Contains("mp3") || mime.Contains("mpeg") ? ".mp3"
                : mime.Contains("ogg")  ? ".ogg"
                : mime.Contains("wav")  ? ".wav"
                : mime.Contains("webm") ? ".webm"
                : ".m4a";

        var uploadsRoot = Path.Combine(env.ContentRootPath, _basePath.TrimStart('.', '/'));
        var audioDir    = Path.Combine(uploadsRoot, "audio");
        Directory.CreateDirectory(audioDir);

        var fileName = $"{Guid.NewGuid()}{ext}";
        var fullPath = Path.Combine(audioDir, fileName);

        using (var stream = new FileStream(fullPath, FileMode.Create))
            await file.CopyToAsync(stream);

        var url = $"/uploads/audio/{fileName}";
        logger.LogInformation("Audio uploaded: {Url}", url);
        return (url, null);
    }

    public async Task<(FileUploadResponse? Response, string? Error)> UploadFileAsync(IFormFile file)
    {
        if (file.Length > _maxFileSizeBytes)
            return (null, $"File size exceeds {_maxFileSizeBytes / 1024 / 1024}MB limit");

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (!_allowedExtensions.Contains(ext))
            return (null, $"File type {ext} is not allowed");

        var now = DateTime.UtcNow;
        var relativePath = Path.Combine(now.Year.ToString(), now.Month.ToString("D2"));
        var fileName = $"{Guid.NewGuid()}{ext}";

        var uploadsRoot = Path.Combine(env.ContentRootPath, _basePath.TrimStart('.', '/'));
        var fullDir = Path.Combine(uploadsRoot, relativePath);

        Directory.CreateDirectory(fullDir);
        var fullPath = Path.Combine(fullDir, fileName);

        using (var stream = new FileStream(fullPath, FileMode.Create))
            await file.CopyToAsync(stream);

        var urlPath = $"/uploads/{relativePath.Replace('\\', '/')}/{fileName}";
        var fileType = DetermineFileType(ext);
        var mimeType = file.ContentType;

        logger.LogInformation("File uploaded: {Path}", urlPath);

        // Для видео — генерируем превью и получаем длительность через FFmpeg
        string? thumbnailPath = null;
        int? durationMs = null;

        if (fileType == "video")
        {
            (thumbnailPath, durationMs) = await ProcessVideoAsync(fullPath, uploadsRoot, _ffmpegPath, _ffprobePath);

            if (thumbnailPath != null)
                logger.LogInformation("Video thumbnail generated: {Thumb}", thumbnailPath);
            else
                logger.LogWarning("FFmpeg не доступен или не удалось создать превью для {Path}", urlPath);
        }

        return (new FileUploadResponse
        {
            Path = urlPath,
            FileName = file.FileName,
            FileSize = file.Length,
            Type = fileType,
            MimeType = mimeType,
            ThumbnailPath = thumbnailPath,
            DurationMs = durationMs
        }, null);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Обработка видео: превью + длительность
    // ──────────────────────────────────────────────────────────────────────

    private async Task<(string? ThumbnailPath, int? DurationMs)> ProcessVideoAsync(
        string videoAbsPath, string uploadsRoot, string ffmpegPath, string ffprobePath)
    {
        var thumbDir = Path.Combine(uploadsRoot, "thumbnails");
        Directory.CreateDirectory(thumbDir);

        var thumbName = $"{Guid.NewGuid()}.jpg";
        var thumbAbs  = Path.Combine(thumbDir, thumbName);
        var thumbUrl  = $"/uploads/thumbnails/{thumbName}";

        string? thumbnailPath = null;
        int? durationMs = null;

        // Пробуем кадр на 1 с, затем — на 0.1 с (для коротких видео)
        foreach (var seek in new[] { "00:00:01", "00:00:00.100" })
        {
            var code = await RunProcessAsync(_ffmpegPath, [
                "-y", "-ss", seek,
                "-i", videoAbsPath,
                "-vframes", "1",
                "-vf", "scale=480:-1",
                "-q:v", "4",
                thumbAbs
            ], timeoutSeconds: 30);

            if (code == 0 && File.Exists(thumbAbs))
            {
                thumbnailPath = thumbUrl;
                break;
            }
        }

        // Длительность через ffprobe
        try
        {
            var (exitCode, output) = await RunProcessWithOutputAsync(_ffprobePath, [
                "-v", "quiet",
                "-print_format", "json",
                "-show_format",
                videoAbsPath
            ], timeoutSeconds: 10);

            if (exitCode == 0 && !string.IsNullOrWhiteSpace(output))
            {
                using var doc = JsonDocument.Parse(output);
                if (doc.RootElement.TryGetProperty("format", out var fmt) &&
                    fmt.TryGetProperty("duration", out var dur) &&
                    double.TryParse(
                        dur.GetString(),
                        System.Globalization.NumberStyles.Any,
                        System.Globalization.CultureInfo.InvariantCulture,
                        out var sec))
                {
                    durationMs = (int)(sec * 1000);
                }
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "ffprobe завершился с ошибкой для {Path}", videoAbsPath);
        }

        return (thumbnailPath, durationMs);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Вспомогательные методы запуска процессов
    // ──────────────────────────────────────────────────────────────────────

    private static async Task<int> RunProcessAsync(
        string executable, string[] args, int timeoutSeconds)
    {
        try
        {
            var psi = new ProcessStartInfo(executable)
            {
                RedirectStandardOutput = true,
                RedirectStandardError  = true,
                UseShellExecute  = false,
                CreateNoWindow   = true
            };
            foreach (var a in args) psi.ArgumentList.Add(a);

            using var process = Process.Start(psi)!;
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds));

            // Читаем stdout/stderr параллельно — иначе буфер заполняется и процесс зависает
            var drainOut = process.StandardOutput.ReadToEndAsync(cts.Token);
            var drainErr = process.StandardError.ReadToEndAsync(cts.Token);

            await process.WaitForExitAsync(cts.Token);
            await Task.WhenAll(drainOut, drainErr);

            return process.ExitCode;
        }
        catch
        {
            return -1;
        }
    }

    private static async Task<(int ExitCode, string Output)> RunProcessWithOutputAsync(
        string executable, string[] args, int timeoutSeconds)
    {
        try
        {
            var psi = new ProcessStartInfo(executable)
            {
                RedirectStandardOutput = true,
                RedirectStandardError  = true,
                UseShellExecute  = false,
                CreateNoWindow   = true
            };
            foreach (var a in args) psi.ArgumentList.Add(a);

            using var process = Process.Start(psi)!;
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds));

            var output = await process.StandardOutput.ReadToEndAsync(cts.Token);
            await process.WaitForExitAsync(cts.Token);
            return (process.ExitCode, output);
        }
        catch
        {
            return (-1, string.Empty);
        }
    }

    // ──────────────────────────────────────────────────────────────────────

    private static string DetermineFileType(string ext) => ext switch
    {
        ".jpg" or ".jpeg" or ".png" or ".gif" or ".webp" => "image",
        ".mp4" or ".mov" or ".avi" or ".mkv"             => "video",
        _                                                 => "document"
    };
}
