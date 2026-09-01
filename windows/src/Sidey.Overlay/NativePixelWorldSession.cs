using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Platform.Windows;
using System.Diagnostics;

namespace Sidey.Overlay;

public sealed record NativePixelWorldSessionOptions(
    IReadOnlySet<string>? ValidationCharacterIds = null,
    bool CollectValidationMetrics = false,
    string? ValidationMetricsPath = null);

public sealed class NativePixelWorldSession : IOverlayHost, IDisposable
{
    private readonly NativeOverlayWindowThread _windows;
    private readonly LayeredPixelWorldRenderer _renderer;
    private readonly ValidationMetricsCollector? _metrics;
    private bool _disposed;

    private NativePixelWorldSession(
        NativeOverlayWindowThread windows,
        LayeredPixelWorldRenderer renderer,
        ValidationMetricsCollector? metrics)
    {
        _windows = windows;
        _renderer = renderer;
        _metrics = metrics;
    }

    public bool IsVisible { get; private set; } = true;

    public string? ValidationMetricsPath => _metrics?.OutputPath;

    public ValidationMetricsSummary? ValidationMetricsSummary => _metrics?.Snapshot();

    public static NativePixelWorldSession Start(
        OverlayRegionPreference preference,
        WorldSnapshot initialSnapshot,
        Action requestComposer,
        Action requestPulse,
        Action<Exception> renderingFailed,
        NativePixelWorldSessionOptions? options = null)
    {
        ArgumentNullException.ThrowIfNull(initialSnapshot);
        ArgumentNullException.ThrowIfNull(requestComposer);
        ArgumentNullException.ThrowIfNull(requestPulse);
        ArgumentNullException.ThrowIfNull(renderingFailed);
        options ??= new NativePixelWorldSessionOptions();

        var normalizedValidationIds = options.ValidationCharacterIds?
            .Select(PixelCharacterCatalog.NormalizeId)
            .ToHashSet(StringComparer.Ordinal);
        if (normalizedValidationIds is { Count: 0 })
        {
            throw new ArgumentException("ValidationCharacterIds cannot be empty.", nameof(options));
        }

        if (normalizedValidationIds is not null
            && initialSnapshot.Members.Any(member => !normalizedValidationIds.Contains(
                PixelCharacterCatalog.NormalizeId(member.CharacterId))))
        {
            throw new ArgumentException(
                "The validation snapshot contains a character outside ValidationCharacterIds.",
                nameof(initialSnapshot));
        }

        var monitor = WindowsMonitorService.Select(preference.MonitorIdentifier);
        var frames = WindowsOverlayRegionLayout.Frames(
            monitor.WorkAreaPixels,
            monitor.Dpi,
            preference);
        var hotspotSize = Math.Max(
            1,
            (int)Math.Round(52d * monitor.Dpi / 96d, MidpointRounding.AwayFromZero));
        var initialHotspot = InitialHotspot(frames.ActivityFrame, preference.Edge, hotspotSize);
        var metrics = options.CollectValidationMetrics
            ? new ValidationMetricsCollector(
                normalizedValidationIds?.ToArray() ?? PixelCharacterCatalog.All.Select(item => item.Id).ToArray(),
                options.ValidationMetricsPath)
            : null;

        NativeOverlayWindowThread? windows = null;
        LayeredPixelWorldRenderer? renderer = null;
        windows = NativeOverlayWindowThread.Start(
            frames.RenderFrame,
            initialHotspot,
            handle =>
            {
                renderer = new LayeredPixelWorldRenderer(
                    handle,
                    frames.ActivityFrame,
                    frames.RenderFrame,
                    monitor.Dpi,
                    preference.Edge,
                    initialSnapshot,
                    bounds => windows?.SetHotspotBounds(bounds),
                    renderingFailed,
                    normalizedValidationIds,
                    metrics);
                return renderer;
            },
            requestComposer,
            requestPulse);
        return new NativePixelWorldSession(
            windows,
            renderer ?? throw new InvalidOperationException("SIDEY renderer did not initialize."),
            metrics);
    }

    public ValueTask ApplyAsync(
        WorldSnapshot snapshot,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _renderer.ApplySnapshot(snapshot);
        return ValueTask.CompletedTask;
    }

    public ValueTask SetVisibleAsync(bool visible, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        ObjectDisposedException.ThrowIf(_disposed, this);
        _windows.SetVisible(visible);
        IsVisible = visible;
        return ValueTask.CompletedTask;
    }

    public Task<string?> ExportValidationMetricsAsync(CancellationToken cancellationToken = default) =>
        _metrics is null
            ? Task.FromResult<string?>(null)
            : ExportAsync(_metrics, cancellationToken);

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _windows.Dispose();
        if (_metrics is not null)
        {
            try
            {
                _metrics.ExportAsync().GetAwaiter().GetResult();
            }
            catch (Exception exception)
            {
                Trace.TraceError("SIDEY validation metrics export failed: {0}", exception);
            }
        }
    }

    private static async Task<string?> ExportAsync(
        ValidationMetricsCollector metrics,
        CancellationToken cancellationToken) =>
        await metrics.ExportAsync(cancellationToken).ConfigureAwait(false);

    private static NativePixelRect InitialHotspot(
        NativePixelRect activity,
        OverlayEdge edge,
        int hotspotSize)
    {
        var tangent = edge is OverlayEdge.Bottom or OverlayEdge.Top
            ? activity.Width / 2d
            : activity.Height / 2d;
        var foot = edge switch
        {
            OverlayEdge.Bottom => (X: activity.X + tangent, Y: (double)(activity.Y + activity.Height)),
            OverlayEdge.Top => (X: activity.X + tangent, Y: (double)activity.Y),
            OverlayEdge.Left => (X: (double)activity.X, Y: activity.Y + tangent),
            OverlayEdge.Right => (X: (double)(activity.X + activity.Width), Y: activity.Y + tangent),
            _ => throw new ArgumentOutOfRangeException(nameof(edge)),
        };
        return new NativePixelRect(
            (int)Math.Round(foot.X - (hotspotSize / 2d), MidpointRounding.AwayFromZero),
            (int)Math.Round(foot.Y - (hotspotSize / 2d), MidpointRounding.AwayFromZero),
            hotspotSize,
            hotspotSize);
    }
}

public static class PixelWorldPreview
{
    public static WorldSnapshot Create(
        IReadOnlyList<string>? characterIds = null,
        long installationSeed = 0x51DE7,
        OverlayEdge edge = OverlayEdge.Bottom)
    {
        var ids = characterIds ?? PixelCharacterCatalog.All.Select(character => character.Id).ToArray();
        var roomId = Guid.Parse("51de7000-0000-0000-0000-000000000100");
        var members = ids.Select((characterId, index) => new PixelWorldMember(
            StableMemberId(index),
            PixelCharacterCatalog.Get(characterId).DisplayName,
            PixelCharacterCatalog.NormalizeId(characterId),
            PresenceState.Online,
            IsTyping: false,
            IsCurrentUser: index == 0)).ToArray();
        return new WorldSnapshot(
            roomId,
            members,
            Array.Empty<ActiveBubble>(),
            Array.Empty<CharacterPulseEvent>(),
            edge,
            installationSeed);
    }

    private static Guid StableMemberId(int index) =>
        Guid.Parse($"51de7000-0000-0000-0000-{index + 1:D12}");
}
