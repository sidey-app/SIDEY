using Sidey.Core.Localization;
using Sidey.Platform.Windows;
using Sidey.Presentation.Services;

namespace Sidey.App;

internal sealed class WindowsUpdateServiceAdapter : IUpdateService
{
    private readonly WindowsUpdateService _service = new();

    public async Task<AvailableUpdate?> CheckAsync(CancellationToken cancellationToken = default)
    {
        WindowsUpdateManifest? manifest = await _service.CheckAsync(cancellationToken);
        return manifest is null
            ? null
            : new AvailableUpdate(manifest.Version, manifest.InstallerUri, manifest.Sha256);
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
            "alpha",
            update.Version,
            $"windows-v{update.Version}",
            update.InstallerUri,
            update.Sha256);
        string installerPath = await _service.DownloadInstallerAsync(
            manifest,
            cancellationToken);
        WindowsUpdateService.LaunchInstaller(installerPath);
    }
}
