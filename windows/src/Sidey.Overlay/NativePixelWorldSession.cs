using System.Diagnostics;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Platform.Windows;

namespace Sidey.Overlay;

public sealed record NativePixelWorldSessionOptions(
    IReadOnlySet<string>? ValidationCharacterIds = null,
    bool CollectValidationMetrics = false,
    string? ValidationMetricsPath = null,
    Action<int>? MessageBubblesPresented = null);

public sealed class NativePixelWorldSession : IOverlayHost, IDisposable
{
    private static readonly TimeSpan ThrowTargetingDuration = TimeSpan.FromSeconds(10);

    private readonly object _throwGate = new();
    private readonly NativeOverlayWindowThread _windows;
    private readonly LayeredPixelWorldRenderer _renderer;
    private readonly ValidationMetricsCollector? _metrics;
    private readonly WindowsMonitorInfo _monitor;
    private readonly OverlayEdge _edge;
    private readonly Timer _taskbarTimer;
    private readonly Timer _throwTargetingTimer;
    private readonly Action<Guid> _requestThrow;
    private readonly Guid?[] _targetUserIds = new Guid?[NativeOverlayWindowThread.MaximumTargetHotspots];
    private readonly NativePixelRect[] _targetBounds = new NativePixelRect[NativeOverlayWindowThread.MaximumTargetHotspots];
    private readonly NativePixelRect[] _appliedTargetBounds = new NativePixelRect[NativeOverlayWindowThread.MaximumTargetHotspots];
    private readonly bool[] _targetWindowsShown = new bool[NativeOverlayWindowThread.MaximumTargetHotspots];
    private int _topmostRefreshCountdown = 20;
    private nint _yieldedShellSurface;
    private Guid? _roomId;
    private bool _requiresRightClickToThrow;
    private bool _realtimeConnected;
    private bool _selfHotspotAvailable;
    private NativePixelRect _lastSelfHotspot = new(0, 0, 1, 1);
    private bool _selfWindowShown = true;
    private bool _throwTargetingActive;
    private bool _disposed;

    private NativePixelWorldSession(
        NativeOverlayWindowThread windows,
        LayeredPixelWorldRenderer renderer,
        ValidationMetricsCollector? metrics,
        WindowsMonitorInfo monitor,
        OverlayEdge edge,
        Guid? roomId,
        Action<Guid> requestThrow,
        bool requiresRightClickToThrow,
        bool realtimeConnected)
    {
        _windows = windows;
        _renderer = renderer;
        _metrics = metrics;
        _monitor = monitor;
        _edge = edge;
        _roomId = roomId;
        _requestThrow = requestThrow;
        _requiresRightClickToThrow = requiresRightClickToThrow;
        _realtimeConnected = realtimeConnected;
        _taskbarTimer = new Timer(
            static state => ((NativePixelWorldSession)state!).RefreshTaskbarInset(),
            this,
            TimeSpan.FromMilliseconds(50),
            TimeSpan.FromMilliseconds(50));
        _throwTargetingTimer = new Timer(
            static state => ((NativePixelWorldSession)state!).ExpireThrowTargeting(),
            this,
            Timeout.InfiniteTimeSpan,
            Timeout.InfiniteTimeSpan);
    }

    public bool IsVisible { get; private set; } = true;

    public string? ValidationMetricsPath => _metrics?.OutputPath;

    public ValidationMetricsSummary? ValidationMetricsSummary => _metrics?.Snapshot();

    public static NativePixelWorldSession Start(
        OverlayRegionPreference preference,
        WorldSnapshot initialSnapshot,
        Action requestComposer,
        Action requestPulse,
        Action<Guid> requestThrow,
        bool requiresRightClickToThrow,
        bool realtimeConnected,
        Action<Exception> renderingFailed,
        NativePixelWorldSessionOptions? options = null)
    {
        ArgumentNullException.ThrowIfNull(initialSnapshot);
        ArgumentNullException.ThrowIfNull(requestComposer);
        ArgumentNullException.ThrowIfNull(requestPulse);
        ArgumentNullException.ThrowIfNull(requestThrow);
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
        var initialTaskbarInset = WindowsTaskbarService.VisibleInset(
            monitor.MonitorPixels,
            monitor.MonitorPixels,
            preference.Edge);
        var frames = WindowsOverlayRegionLayout.Frames(
            monitor.MonitorPixels,
            monitor.Dpi,
            preference);
        var hotspotSize = Math.Max(
            1,
            (int)Math.Round(52d * monitor.Dpi / 96d, MidpointRounding.AwayFromZero));
        var initialHotspot = InitialHotspot(
            frames.ActivityFrame,
            preference.Edge,
            hotspotSize,
            initialTaskbarInset);
        var metrics = options.CollectValidationMetrics
            ? new ValidationMetricsCollector(
                normalizedValidationIds?.ToArray() ?? PixelCharacterCatalog.All.Select(item => item.Id).ToArray(),
                options.ValidationMetricsPath)
            : null;

        NativeOverlayWindowThread? windows = null;
        LayeredPixelWorldRenderer? renderer = null;
        NativePixelWorldSession? session = null;
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
                    (self, targets) => session?.UpdateHotspots(self, targets),
                    renderingFailed,
                    options.MessageBubblesPresented,
                    normalizedValidationIds,
                    metrics,
                    initialTaskbarInset);
                return renderer;
            },
            requestComposer,
            requestPulse,
            () => session?.ActivateThrowTargeting(),
            index => session?.ActivateTarget(index));
        session = new NativePixelWorldSession(
            windows,
            renderer ?? throw new InvalidOperationException("SIDEY renderer did not initialize."),
            metrics,
            monitor,
            preference.Edge,
            initialSnapshot.RoomId,
            requestThrow,
            requiresRightClickToThrow,
            realtimeConnected);
        return session;
    }

    public ValueTask ApplyAsync(
        WorldSnapshot snapshot,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (_roomId != snapshot.RoomId)
        {
            lock (_throwGate)
            {
                _roomId = snapshot.RoomId;
                CancelThrowTargetingWithinGate();
                ClearTargetsWithinGate();
            }
        }
        _renderer.ApplySnapshot(snapshot);
        return ValueTask.CompletedTask;
    }

    public ValueTask SetVisibleAsync(bool visible, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        ObjectDisposedException.ThrowIf(_disposed, this);
        _windows.SetVisible(visible);
        IsVisible = visible;
        if (visible && !_selfHotspotAvailable)
        {
            _windows.SetHotspotBounds(_lastSelfHotspot, visible: false);
        }
        _selfWindowShown = visible && _selfHotspotAvailable;
        if (!visible)
        {
            lock (_throwGate)
            {
                CancelThrowTargetingWithinGate();
                _windows.HideTargetHotspots();
                Array.Clear(_targetWindowsShown);
            }
        }
        else
        {
            lock (_throwGate)
            {
                RefreshTargetVisibilityWithinGate();
            }
        }
        return ValueTask.CompletedTask;
    }

    public void ConfigureThrowInteraction(bool requiresRightClickToThrow, bool realtimeConnected)
    {
        lock (_throwGate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            _requiresRightClickToThrow = requiresRightClickToThrow;
            _realtimeConnected = realtimeConnected;
            CancelThrowTargetingWithinGate();
            RefreshTargetVisibilityWithinGate();
        }
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
        _taskbarTimer.Change(Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
        _taskbarTimer.Dispose();
        _throwTargetingTimer.Change(Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
        _throwTargetingTimer.Dispose();
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

    private void ActivateThrowTargeting()
    {
        lock (_throwGate)
        {
            if (_disposed || !_requiresRightClickToThrow || !_realtimeConnected
                || !IsVisible || !_selfHotspotAvailable)
            {
                return;
            }

            _throwTargetingActive = true;
            _throwTargetingTimer.Change(ThrowTargetingDuration, Timeout.InfiniteTimeSpan);
            RefreshTargetVisibilityWithinGate();
        }
    }

    private void ExpireThrowTargeting()
    {
        lock (_throwGate)
        {
            if (_disposed)
            {
                return;
            }

            _throwTargetingActive = false;
            RefreshTargetVisibilityWithinGate();
        }
    }

    private void ActivateTarget(int index)
    {
        Guid? targetUserId;
        lock (_throwGate)
        {
            if (_disposed || !TargetsEnabledWithinGate()
                || index < 0 || index >= _targetUserIds.Length)
            {
                return;
            }

            targetUserId = _targetUserIds[index];
        }

        if (targetUserId is { } userId)
        {
            _requestThrow(userId);
        }
    }

    private void UpdateHotspots(
        NativePixelRect? self,
        IReadOnlyList<CharacterHotspotFrame> targets)
    {
        lock (_throwGate)
        {
            if (_disposed)
            {
                return;
            }

            _selfHotspotAvailable = self is not null;
            if (self is { } selfBounds)
            {
                if (!_selfWindowShown || MovedAtLeastOneDip(_lastSelfHotspot, selfBounds))
                {
                    _windows.SetHotspotBounds(selfBounds, IsVisible);
                    _lastSelfHotspot = selfBounds;
                }
                _selfWindowShown = IsVisible;
            }
            else
            {
                if (_selfWindowShown)
                {
                    _windows.SetHotspotBounds(_lastSelfHotspot, visible: false);
                    _selfWindowShown = false;
                }
                CancelThrowTargetingWithinGate();
            }

            var count = Math.Min(targets.Count, _targetUserIds.Length);
            for (var index = 0; index < count; index++)
            {
                _targetUserIds[index] = targets[index].UserId;
                _targetBounds[index] = targets[index].Bounds;
            }
            for (var index = count; index < _targetUserIds.Length; index++)
            {
                _targetUserIds[index] = null;
            }
            RefreshTargetVisibilityWithinGate();
        }
    }

    private bool TargetsEnabledWithinGate() =>
        IsVisible
        && _realtimeConnected
        && _selfHotspotAvailable
        && (!_requiresRightClickToThrow || _throwTargetingActive);

    private void RefreshTargetVisibilityWithinGate()
    {
        var enabled = TargetsEnabledWithinGate();
        for (var index = 0; index < _targetUserIds.Length; index++)
        {
            var visible = enabled && _targetUserIds[index] is not null;
            if (visible)
            {
                if (!_targetWindowsShown[index]
                    || MovedAtLeastOneDip(_appliedTargetBounds[index], _targetBounds[index]))
                {
                    _windows.SetTargetHotspotBounds(index, _targetBounds[index], visible: true);
                    _appliedTargetBounds[index] = _targetBounds[index];
                }
                _targetWindowsShown[index] = true;
            }
            else if (_targetWindowsShown[index])
            {
                _windows.SetTargetHotspotBounds(
                    index,
                    _targetBounds[index].IsValid ? _targetBounds[index] : new NativePixelRect(0, 0, 1, 1),
                    visible: false);
                _targetWindowsShown[index] = false;
            }
        }
    }

    private void CancelThrowTargetingWithinGate()
    {
        _throwTargetingActive = false;
        _throwTargetingTimer.Change(Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
    }

    private void ClearTargetsWithinGate()
    {
        Array.Clear(_targetUserIds);
        Array.Clear(_targetWindowsShown);
        _windows.HideTargetHotspots();
    }

    private bool MovedAtLeastOneDip(NativePixelRect previous, NativePixelRect current)
    {
        if (!previous.IsValid)
        {
            return true;
        }
        var minimumPixels = Math.Max(1d, _monitor.Dpi / 96d);
        var previousCenterX = previous.X + (previous.Width / 2d);
        var previousCenterY = previous.Y + (previous.Height / 2d);
        var currentCenterX = current.X + (current.Width / 2d);
        var currentCenterY = current.Y + (current.Height / 2d);
        return Math.Abs(currentCenterX - previousCenterX) >= minimumPixels
            || Math.Abs(currentCenterY - previousCenterY) >= minimumPixels;
    }

    private void RefreshTaskbarInset()
    {
        if (_disposed)
        {
            return;
        }

        try
        {
            _renderer.SetEdgeInset(WindowsTaskbarService.VisibleInset(
                _monitor.MonitorPixels,
                _monitor.MonitorPixels,
                _edge));
            nint shellSurface = WindowsShellSurfaceDetector.ForegroundSurface();
            if (IsVisible && shellSurface != nint.Zero)
            {
                if (shellSurface != _yieldedShellSurface
                    || Interlocked.Decrement(ref _topmostRefreshCountdown) <= 0)
                {
                    Interlocked.Exchange(ref _topmostRefreshCountdown, 20);
                    _windows.YieldBehind(shellSurface);
                    _yieldedShellSurface = shellSurface;
                }
            }
            else if (IsVisible
                && (_yieldedShellSurface != nint.Zero
                    || Interlocked.Decrement(ref _topmostRefreshCountdown) <= 0))
            {
                Interlocked.Exchange(ref _topmostRefreshCountdown, 20);
                _windows.EnsureTopmost();
                _yieldedShellSurface = nint.Zero;
            }
        }
        catch (ObjectDisposedException) when (_disposed)
        {
        }
        catch (Exception exception)
        {
            Trace.TraceError("SIDEY taskbar tracking failed: {0}", exception);
        }
    }

    private static NativePixelRect InitialHotspot(
        NativePixelRect activity,
        OverlayEdge edge,
        int hotspotSize,
        int edgeInset)
    {
        var tangent = edge is OverlayEdge.Bottom or OverlayEdge.Top
            ? activity.Width / 2d
            : activity.Height / 2d;
        var foot = edge switch
        {
            OverlayEdge.Bottom => (
                X: activity.X + tangent,
                Y: (double)(activity.Y + activity.Height - edgeInset)),
            OverlayEdge.Top => (
                X: activity.X + tangent,
                Y: (double)(activity.Y + edgeInset)),
            OverlayEdge.Left => (
                X: (double)(activity.X + edgeInset),
                Y: activity.Y + tangent),
            OverlayEdge.Right => (
                X: (double)(activity.X + activity.Width - edgeInset),
                Y: activity.Y + tangent),
            _ => throw new ArgumentOutOfRangeException(nameof(edge)),
        };
        var tangentOrigin = edge is OverlayEdge.Bottom or OverlayEdge.Top
            ? (int)Math.Round(foot.X - (hotspotSize / 2d), MidpointRounding.AwayFromZero)
            : (int)Math.Round(foot.Y - (hotspotSize / 2d), MidpointRounding.AwayFromZero);
        return edge switch
        {
            OverlayEdge.Bottom => new NativePixelRect(
                tangentOrigin,
                (int)Math.Round(foot.Y, MidpointRounding.AwayFromZero) - hotspotSize,
                hotspotSize,
                hotspotSize),
            OverlayEdge.Top => new NativePixelRect(
                tangentOrigin,
                (int)Math.Round(foot.Y, MidpointRounding.AwayFromZero),
                hotspotSize,
                hotspotSize),
            OverlayEdge.Left => new NativePixelRect(
                (int)Math.Round(foot.X, MidpointRounding.AwayFromZero),
                tangentOrigin,
                hotspotSize,
                hotspotSize),
            OverlayEdge.Right => new NativePixelRect(
                (int)Math.Round(foot.X, MidpointRounding.AwayFromZero) - hotspotSize,
                tangentOrigin,
                hotspotSize,
                hotspotSize),
            _ => throw new ArgumentOutOfRangeException(nameof(edge)),
        };
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
            Array.Empty<CharacterThrowEvent>(),
            edge,
            installationSeed);
    }

    private static Guid StableMemberId(int index) =>
        Guid.Parse($"51de7000-0000-0000-0000-{index + 1:D12}");
}
