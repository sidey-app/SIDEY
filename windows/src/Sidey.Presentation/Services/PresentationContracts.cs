namespace Sidey.Presentation.Services;

public sealed record MonitorOption(string Identifier, string Name, bool IsPrimary);

public sealed record ValidationMetricsSnapshot(
    double ElapsedSeconds,
    int SampleCount,
    double MaximumFrameMilliseconds,
    long CurrentWorkingSetBytes,
    long PeakWorkingSetBytes,
    uint MaximumGdiHandles,
    uint MaximumUserHandles);

public sealed record AvailableUpdate(
    string Version,
    Uri? InstallerUri = null,
    string? Sha256 = null,
    Uri? ReleaseNotesUri = null);

public interface IUpdateService
{
    string CurrentVersion { get; }

    DateTimeOffset? LastCheckedAt { get; }

    Uri CurrentReleaseNotesUri { get; }

    Task<AvailableUpdate?> CheckAsync(CancellationToken cancellationToken = default);

    Task DownloadAndLaunchInstallerAsync(
        AvailableUpdate update,
        CancellationToken cancellationToken = default);

    Task OpenReleaseNotesAsync(Uri releaseNotesUri);
}
