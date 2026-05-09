using System.Diagnostics;
using System.Text.Json;
using CaspianMessenger.Server.Data;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Services;

/// <summary>
/// Runs once at startup: generates thumbnails and duration for video attachments
/// that were uploaded before FFmpeg support was added (thumbnailPath IS NULL).
/// </summary>
public class VideoThumbnailMigrationService(
    IServiceScopeFactory scopeFactory,
    IConfiguration config,
    IWebHostEnvironment env,
    ILogger<VideoThumbnailMigrationService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Небольшая задержка — дать серверу полностью запуститься
        await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);

        var ffmpegPath  = config["FFmpeg:FfmpegPath"]  ?? "ffmpeg";
        var ffprobePath = config["FFmpeg:FfprobePath"] ?? "ffprobe";
        var basePath    = config["FileStorage:BasePath"] ?? "./uploads";
        var uploadsRoot = Path.Combine(env.ContentRootPath, basePath.TrimStart('.', '/', '\\'));
        var thumbDir    = Path.Combine(uploadsRoot, "thumbnails");
        Directory.CreateDirectory(thumbDir);

        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var pending = await db.Attachments
            .Where(a => a.Type == "video" && a.ThumbnailPath == null)
            .ToListAsync(stoppingToken);

        if (pending.Count == 0)
        {
            logger.LogInformation("VideoThumbnailMigration: nothing to process");
            return;
        }

        logger.LogInformation("VideoThumbnailMigration: processing {Count} video(s) without thumbnail", pending.Count);

        int ok = 0, fail = 0;

        foreach (var attachment in pending)
        {
            if (stoppingToken.IsCancellationRequested) break;

            // Восстанавливаем абсолютный путь из URL-пути (/uploads/... → disk)
            var relativeDisk = attachment.FilePath
                .TrimStart('/')
                .Replace('/', Path.DirectorySeparatorChar);
            var videoAbs = Path.Combine(env.ContentRootPath, relativeDisk);

            if (!File.Exists(videoAbs))
            {
                logger.LogWarning("VideoThumbnailMigration: file not found on disk — {Path}", attachment.FilePath);
                fail++;
                continue;
            }

            var thumbName = $"{Guid.NewGuid()}.jpg";
            var thumbAbs  = Path.Combine(thumbDir, thumbName);
            var thumbUrl  = $"/uploads/thumbnails/{thumbName}";

            // Превью
            bool thumbOk = false;
            foreach (var seek in new[] { "00:00:01", "00:00:00.100" })
            {
                var code = await RunAsync(ffmpegPath, [
                    "-y", "-ss", seek,
                    "-i", videoAbs,
                    "-vframes", "1",
                    "-vf", "scale=480:-1",
                    "-q:v", "4",
                    thumbAbs
                ], stoppingToken);

                if (code == 0 && File.Exists(thumbAbs))
                {
                    attachment.ThumbnailPath = thumbUrl;
                    thumbOk = true;
                    break;
                }
            }

            // Длительность
            try
            {
                var (exitCode, output) = await RunWithOutputAsync(ffprobePath, [
                    "-v", "quiet",
                    "-print_format", "json",
                    "-show_format",
                    videoAbs
                ], stoppingToken);

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
                        attachment.DurationMs = (int)(sec * 1000);
                    }
                }
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "VideoThumbnailMigration: ffprobe failed for {Path}", attachment.FilePath);
            }

            if (thumbOk)
            {
                ok++;
                logger.LogInformation("VideoThumbnailMigration: generated thumbnail for {Path}", attachment.FilePath);
            }
            else
            {
                fail++;
                logger.LogWarning("VideoThumbnailMigration: could not generate thumbnail for {Path}", attachment.FilePath);
            }
        }

        await db.SaveChangesAsync(stoppingToken);
        logger.LogInformation("VideoThumbnailMigration: done — {Ok} ok, {Fail} failed", ok, fail);
    }

    private static async Task<int> RunAsync(string exe, string[] args, CancellationToken ct)
    {
        try
        {
            var psi = new ProcessStartInfo(exe)
            {
                RedirectStandardOutput = true,
                RedirectStandardError  = true,
                UseShellExecute  = false,
                CreateNoWindow   = true
            };
            foreach (var a in args) psi.ArgumentList.Add(a);

            using var p   = Process.Start(psi)!;
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(
                ct, new CancellationTokenSource(TimeSpan.FromSeconds(30)).Token);

            var drainOut = p.StandardOutput.ReadToEndAsync(cts.Token);
            var drainErr = p.StandardError.ReadToEndAsync(cts.Token);
            await p.WaitForExitAsync(cts.Token);
            await Task.WhenAll(drainOut, drainErr);
            return p.ExitCode;
        }
        catch { return -1; }
    }

    private static async Task<(int, string)> RunWithOutputAsync(string exe, string[] args, CancellationToken ct)
    {
        try
        {
            var psi = new ProcessStartInfo(exe)
            {
                RedirectStandardOutput = true,
                RedirectStandardError  = true,
                UseShellExecute  = false,
                CreateNoWindow   = true
            };
            foreach (var a in args) psi.ArgumentList.Add(a);

            using var p   = Process.Start(psi)!;
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(
                ct, new CancellationTokenSource(TimeSpan.FromSeconds(10)).Token);

            var outTask = p.StandardOutput.ReadToEndAsync(cts.Token);
            var errTask = p.StandardError.ReadToEndAsync(cts.Token);
            await p.WaitForExitAsync(cts.Token);
            var output = await outTask;
            await errTask;
            return (p.ExitCode, output);
        }
        catch { return (-1, string.Empty); }
    }
}
