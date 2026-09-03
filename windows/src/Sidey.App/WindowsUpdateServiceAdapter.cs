using System.Diagnostics;
using System.Globalization;
using Sidey.Core.Localization;
using Sidey.Core.Storage;
using Sidey.Platform.Windows;
using Sidey.Presentation.Services;

namespace Sidey.App;

internal sealed class WindowsUpdateServiceAdapter : IUpdateService
{
    private static readonly string LastCheckedPath = Path.Combine(
        SideyStoragePaths.LocalApplicationDataRoot(),
        "SIDEY",
        "update-last-checked.txt");
    private readonly WindowsUpdateService _service = new();

    public WindowsUpdateServiceAdapter()
    {
        LastCheckedAt = ReadLastCheckedAt();
    }

    public string CurrentVersion => WindowsUpdateService.CurrentVersion;

    public DateTimeOffset? LastCheckedAt { get; private set; }

    public Uri CurrentReleaseNotesUri => ReleaseNotesUri(CurrentVersion);

    public async Task<AvailableUpdate?> CheckAsync(CancellationToken cancellationToken = default)
    {
        StartupDiagnostics.Stage("update-check-started");
        try
        {
            WindowsUpdateManifest? manifest = await _service.CheckAsync(cancellationToken);
            LastCheckedAt = DateTimeOffset.UtcNow;
            SaveLastCheckedAt(LastCheckedAt.Value);
            StartupDiagnostics.Stage(
                $"update-check-completed result={(manifest is null ? "latest" : "available")}");
            return manifest is null
                ? null
                : new AvailableUpdate(
                    manifest.Version,
                    manifest.InstallerUri,
                    manifest.Sha256,
                    ReleaseNotesUri(manifest.Version));
        }
        catch (Exception exception)
        {
            StartupDiagnostics.NonFatal("update-check", exception);
            throw;
        }
    }

    public async Task DownloadAndLaunchInstallerAsync(
        AvailableUpdate update,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(update);
        if (update.InstallerUri is null || string.IsNullOrWhiteSpace(update.Sha256))
        {
            throw new InvalidDataException(I18n.Get("update.missingInstaller"));
        }

        var manifest = new WindowsUpdateManifest(
            "production",
            update.Version,
            $"windows-v{update.Version}",
            update.InstallerUri,
            update.Sha256);
        string installerPath = await _service.DownloadInstallerAsync(
            manifest,
            cancellationToken);
        WindowsUpdateService.LaunchInstaller(installerPath);
    }

    public Task OpenReleaseNotesAsync(Uri releaseNotesUri)
    {
        ArgumentNullException.ThrowIfNull(releaseNotesUri);
        if (!StringComparer.OrdinalIgnoreCase.Equals(releaseNotesUri.Scheme, Uri.UriSchemeHttps)
            || !StringComparer.OrdinalIgnoreCase.Equals(releaseNotesUri.Host, "github.com")
            || !releaseNotesUri.AbsolutePath.StartsWith(
                "/sidey-app/SIDEY/releases/tag/windows-v",
                StringComparison.Ordinal))
        {
            throw new InvalidOperationException("The SIDEY release notes URL is not trusted.");
        }

        Process.Start(new ProcessStartInfo(releaseNotesUri.AbsoluteUri)
        {
            UseShellExecute = true,
        });
        StartupDiagnostics.Stage("release-notes-opened");
        return Task.CompletedTask;
    }

    private static Uri ReleaseNotesUri(string version) => new(
        $"https://github.com/sidey-app/SIDEY/releases/tag/windows-v{version}");

    private static DateTimeOffset? ReadLastCheckedAt()
    {
        try
        {
            string value = File.ReadAllText(LastCheckedPath).Trim();
            return DateTimeOffset.TryParseExact(
                value,
                "O",
                CultureInfo.InvariantCulture,
                DateTimeStyles.RoundtripKind,
                out DateTimeOffset parsed)
                ? parsed.ToUniversalTime()
                : null;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

    private static void SaveLastCheckedAt(DateTimeOffset timestamp)
    {
        try
        {
            string? directory = Path.GetDirectoryName(LastCheckedPath);
            if (directory is null)
            {
                return;
            }

            Directory.CreateDirectory(directory);
            File.WriteAllText(
                LastCheckedPath,
                timestamp.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture));
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}
