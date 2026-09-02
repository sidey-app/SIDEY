using System.Diagnostics;
using Sidey.Core.Domain;
using Sidey.Core.Overlay;
using Sidey.Platform.Windows;

namespace Sidey.Overlay;

internal sealed class LayeredPixelWorldRenderer : IDisposable
{
    private const int FramesPerSecond = 30;
    private const double FixedDeltaTime = 1d / FramesPerSecond;
    private const double EdgeInsetAnimationSpeedDipPerSecond = 72d;
    private const int NameplateCharacterGapPixels = 10;
    private const double DozeRestingOpacity = 0.55d;
    private const double DozeFloatingDistanceDip = 3d;
    private static readonly IReadOnlyList<RectD> NoAvoidanceRects = Array.Empty<RectD>();

    private readonly object _gate = new();
    private readonly NativePixelRect _activityBounds;
    private readonly NativePixelRect _renderBounds;
    private readonly int _hotspotPixelSize;
    private readonly int _integerScale;
    private readonly int _dozeFloatingDistancePixels;
    private readonly OverlayEdge _edge;
    private readonly Action<NativePixelRect> _hotspotMoved;
    private readonly Action<Exception> _renderingFailed;
    private readonly ValidationMetricsCollector? _metrics;
    private readonly Random _random;
    private readonly long _initialPositionSeed;
    private readonly EdgeTrackGeometry _geometry;
    private readonly PixelCharacterFrameCache _frameCache;
    private readonly PixelTextVisualCache _textVisuals;
    private readonly NativeLayeredBitmap _surface;
    private readonly List<WorldNode> _nodes = [];
    private readonly List<PixelMovementAgent> _agents = [];
    private readonly Dictionary<Guid, WorldNode> _nodeById = [];
    private readonly HashSet<Guid> _stoppedIds = [];
    private readonly HashSet<Guid> _incomingMemberIds = [];
    private readonly Dictionary<Guid, long> _pulseStartedAt = [];
    private readonly Dictionary<Guid, long> _dozeStartedAt = [];
    private readonly Dictionary<Guid, ActiveBubble> _bubbleBySender = [];
    private readonly List<Guid> _expiredBubbleSenders = [];
    private readonly List<MessageBubbleTrackBounds> _bubbleTrackBounds = [];
    private readonly PixelMovementScratch _movementScratch = new();
    private readonly MessageBubbleCollisionScratch _bubbleCollisionScratch = new();
    private readonly CharacterPulseReplayGuard _pulseReplayGuard = new();
    private readonly Timer _timer;
    private NativePixelRect? _lastHotspotBounds;
    private double _hotspotTrackingElapsed = double.PositiveInfinity;
    private long _tick;
    private int _tickRunning;
    private double _edgeInsetPixels;
    private int _targetEdgeInsetPixels;
    private bool _faulted;
    private bool _disposed;

    internal LayeredPixelWorldRenderer(
        nint windowHandle,
        NativePixelRect activityBounds,
        NativePixelRect renderBounds,
        uint dpi,
        OverlayEdge edge,
        WorldSnapshot initialSnapshot,
        Action<NativePixelRect> hotspotMoved,
        Action<Exception> renderingFailed,
        IReadOnlySet<string>? cachedCharacterIds = null,
        ValidationMetricsCollector? metrics = null,
        int initialEdgeInsetPixels = 0)
    {
        if (!activityBounds.IsValid || !renderBounds.IsValid)
        {
            throw new ArgumentOutOfRangeException(nameof(activityBounds));
        }

        _activityBounds = activityBounds;
        _renderBounds = renderBounds;
        _hotspotMoved = hotspotMoved ?? throw new ArgumentNullException(nameof(hotspotMoved));
        _renderingFailed = renderingFailed ?? throw new ArgumentNullException(nameof(renderingFailed));
        _metrics = metrics;
        _edge = edge;
        _edgeInsetPixels = ClampEdgeInset(initialEdgeInsetPixels);
        _targetEdgeInsetPixels = (int)_edgeInsetPixels;
        _integerScale = PixelScalePolicy.IntegerScale(dpi);
        _dozeFloatingDistancePixels = Math.Max(1, DipToPixels(DozeFloatingDistanceDip, dpi));
        _hotspotPixelSize = Math.Max(1, DipToPixels(52, dpi));
        _initialPositionSeed = OverlayPlacementPolicy.CreateSessionSeed(
            initialSnapshot.InstallationSeed);
        _random = new Random(OverlayPlacementPolicy.RandomSeed(_initialPositionSeed));
        _geometry = new EdgeTrackGeometry(
            new RectD(0, 0, activityBounds.Width, activityBounds.Height),
            edge,
            Math.Max(24 * _integerScale, _hotspotPixelSize));
        var assetRoot = CharacterAssetPathResolver.Resolve();
        PixelCharacterFrameCache? frameCache = null;
        PixelTextVisualCache? textVisuals = null;
        NativeLayeredBitmap? surface = null;
        try
        {
            var initialCharacterIds = cachedCharacterIds
                ?? initialSnapshot.Members
                    .Select(member => PixelCharacterCatalog.NormalizeId(member.CharacterId))
                    .ToHashSet(StringComparer.Ordinal);
            frameCache = new PixelCharacterFrameCache(
                assetRoot,
                _integerScale,
                edge,
                initialCharacterIds);
            textVisuals = new PixelTextVisualCache(dpi, edge);
            surface = new NativeLayeredBitmap(
                windowHandle,
                renderBounds.Width,
                renderBounds.Height);
            _frameCache = frameCache;
            _textVisuals = textVisuals;
            _surface = surface;
            _pulseReplayGuard.SeedExisting(initialSnapshot.Pulses);
            ApplySnapshotWithinGate(initialSnapshot with { Pulses = [] });
            RenderFrame();
            _timer = new Timer(
                static state => ((LayeredPixelWorldRenderer)state!).TickSafely(),
                this,
                TimeSpan.FromSeconds(FixedDeltaTime),
                TimeSpan.FromSeconds(FixedDeltaTime));
        }
        catch
        {
            surface?.Dispose();
            textVisuals?.Dispose();
            frameCache?.Dispose();
            throw;
        }
    }

    public void ApplySnapshot(WorldSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            ApplySnapshotWithinGate(snapshot);
        }
    }

    public void SetEdgeInset(int edgeInsetPixels)
    {
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            _targetEdgeInsetPixels = ClampEdgeInset(edgeInsetPixels);
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            _timer.Change(Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
            _timer.Dispose();
            _surface.Dispose();
            _textVisuals.Dispose();
            _frameCache.Dispose();
        }
    }

    private void TickSafely()
    {
        if (Interlocked.Exchange(ref _tickRunning, 1) != 0)
        {
            return;
        }

        var started = Stopwatch.GetTimestamp();
        try
        {
            Tick();
        }
        catch (Exception exception)
        {
            lock (_gate)
            {
                if (_disposed || _faulted)
                {
                    return;
                }

                _faulted = true;
                _timer.Change(Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
            }

            try
            {
                _renderingFailed(exception);
            }
            catch (Exception reportingException)
            {
                Trace.TraceError(
                    "SIDEY renderer failure callback also failed. Renderer: {0}; callback: {1}",
                    exception,
                    reportingException);
            }
        }
        finally
        {
            try
            {
                _metrics?.RecordFrame(Stopwatch.GetElapsedTime(started));
            }
            catch (Exception exception)
            {
                Trace.TraceError("SIDEY validation metrics sampling failed: {0}", exception);
            }
            finally
            {
                Volatile.Write(ref _tickRunning, 0);
            }
        }
    }

    private void Tick()
    {
        lock (_gate)
        {
            if (_disposed || _faulted)
            {
                return;
            }

            AnimateEdgeInset();

            foreach (var node in _nodes)
            {
                if (Math.Abs(node.Agent.Target - node.Agent.TrackPosition) <= 2d)
                {
                    var length = Math.Max(0d, _geometry.TrackUpperBound - _geometry.TrackLowerBound);
                    node.Agent.Target = _geometry.TrackLowerBound + (_random.NextDouble() * length);
                    node.Agent.IdleRemaining = 0.6d + (_random.NextDouble() * 1.4d);
                }
            }

            PixelMovementSimulation.Step(
                _agents,
                FixedDeltaTime,
                _geometry,
                NoAvoidanceRects,
                _stoppedIds,
                _movementScratch);
            _expiredBubbleSenders.Clear();
            var now = DateTimeOffset.UtcNow;
            foreach (var bubble in _bubbleBySender)
            {
                if (bubble.Value.ExpiresAt <= now)
                {
                    _expiredBubbleSenders.Add(bubble.Key);
                }
            }
            foreach (var senderId in _expiredBubbleSenders)
            {
                _bubbleBySender.Remove(senderId);
            }
            _bubbleTrackBounds.Clear();
            foreach (var bubble in _bubbleBySender.Values)
            {
                if (!_nodeById.TryGetValue(bubble.SenderId, out var node))
                {
                    continue;
                }
                var visual = _textVisuals.Get(bubble.SenderId).MessageBubble;
                if (visual is null)
                {
                    continue;
                }
                var tangentWidth = _edge is OverlayEdge.Left or OverlayEdge.Right
                    ? visual.Height
                    : visual.Width;
                var halfWidth = tangentWidth / 2d;
                _bubbleTrackBounds.Add(new MessageBubbleTrackBounds(
                    bubble.SenderId,
                    node.Agent.TrackPosition - halfWidth,
                    node.Agent.TrackPosition + halfWidth));
            }
            MessageBubbleCollisionResolver.Apply(
                _agents,
                _bubbleTrackBounds,
                FixedDeltaTime,
                _geometry,
                _bubbleCollisionScratch);
            _tick++;
            _hotspotTrackingElapsed = Math.Min(1d, _hotspotTrackingElapsed + FixedDeltaTime);
            RenderFrame();
        }
    }

    private void RenderFrame()
    {
        Span<byte> destinationPixels = _surface.Pixels;
        destinationPixels.Clear();
        NativePixelRect? currentUserHotspot = null;
        foreach (var node in _nodes)
        {
            var cached = _frameCache.Get(node.Member.CharacterId);
            var moving = Math.Abs(node.Agent.Velocity) >= 0.5d;
            var frame = FrameIndex(node.Member.Presence, moving, cached.Definition.Frames);
            var pulseScale = PulseScale(node.Member.Id);
            var foot = FootPoint(node.Agent.TrackPosition);
            var baseDestination = DestinationForFoot(
                foot,
                cached.PixelSize,
                cached.Definition.FootBaselinePixel * _integerScale,
                cached.OnlineContentBounds,
                1d);
            var destination = DestinationForFoot(
                foot,
                cached.PixelSize,
                cached.Definition.FootBaselinePixel * _integerScale,
                cached.OnlineContentBounds,
                pulseScale);
            Composite(
                destinationPixels,
                cached.Frame(frame, node.Agent.Velocity < -0.1d),
                cached.PixelSize,
                destination.X - _renderBounds.X,
                destination.Y - _renderBounds.Y,
                pulseScale,
                node.Member.Presence == PresenceState.Offline ? 0.75d : 1d,
                desaturate: node.Member.Presence == PresenceState.Offline);

            if (node.Member.IsCurrentUser)
            {
                currentUserHotspot = HotspotBounds(baseDestination, cached.PixelSize, foot);
            }

            var visuals = _textVisuals.Get(node.Member.Id);
            var nameplate = PlaceNameplate(
                baseDestination,
                cached.PixelSize,
                visuals.Nameplate,
                cached.OnlineContentBounds);
            CompositeVisual(destinationPixels, visuals.Nameplate, nameplate.X, nameplate.Y);
            var bubble = _bubbleBySender.ContainsKey(node.Member.Id)
                ? visuals.MessageBubble
                : visuals.TypingBubble;
            if (bubble is not null)
            {
                var bubblePosition = PlaceBeyondNameplate(
                    baseDestination,
                    cached.PixelSize,
                    bubble,
                    gap: 4,
                    visuals.Nameplate,
                    nameplate);
                CompositeVisual(destinationPixels, bubble, bubblePosition.X, bubblePosition.Y);
            }
            if (visuals.Doze is { } doze)
            {
                var dozePosition = PlaceDoze(baseDestination, cached.PixelSize, doze);
                long startedAt = _dozeStartedAt.GetValueOrDefault(node.Member.Id, _tick);
                var progress = DozeAnimationProgress(_tick - startedAt);
                var animatedPosition = FloatDozeTowardInterior(
                    dozePosition,
                    (int)Math.Round(progress * _dozeFloatingDistancePixels));
                CompositeVisual(
                    destinationPixels,
                    doze,
                    animatedPosition.X,
                    animatedPosition.Y,
                    DozeRestingOpacity + (progress * (1d - DozeRestingOpacity)));
            }
        }

        _surface.Present(_renderBounds.X, _renderBounds.Y);
        if (currentUserHotspot is { } hotspot)
        {
            MoveHotspotIfNeeded(hotspot);
        }
    }

    private void ApplySnapshotWithinGate(WorldSnapshot snapshot)
    {
        _frameCache.RetainCharacters(snapshot.Members.Select(member => member.CharacterId));
        _incomingMemberIds.Clear();
        foreach (var member in snapshot.Members)
        {
            _incomingMemberIds.Add(member.Id);
        }
        for (var index = _nodes.Count - 1; index >= 0; index--)
        {
            var node = _nodes[index];
            if (_incomingMemberIds.Contains(node.Member.Id))
            {
                continue;
            }

            _nodes.RemoveAt(index);
            _agents.Remove(node.Agent);
            _nodeById.Remove(node.Member.Id);
            _stoppedIds.Remove(node.Member.Id);
            _pulseStartedAt.Remove(node.Member.Id);
            _dozeStartedAt.Remove(node.Member.Id);
        }

        foreach (var member in snapshot.Members)
        {
            if (_nodeById.TryGetValue(member.Id, out var existing))
            {
                bool wasAway = existing.Member.Presence == PresenceState.Away;
                existing.Member = member with
                {
                    CharacterId = PixelCharacterCatalog.NormalizeId(member.CharacterId),
                };
                bool isAway = existing.Member.Presence == PresenceState.Away;
                if (!wasAway && isAway)
                {
                    _dozeStartedAt[member.Id] = _tick;
                }
                else if (!isAway)
                {
                    _dozeStartedAt.Remove(member.Id);
                }
            }
            else
            {
                var fraction = OverlayPlacementPolicy.Fraction(member.Id, _initialPositionSeed);
                var targetFraction = OverlayPlacementPolicy.Fraction(
                    member.Id,
                    _initialPositionSeed,
                    OverlayPlacementPolicy.TargetSalt);
                var position = _geometry.TrackLowerBound
                    + (fraction * (_geometry.TrackUpperBound - _geometry.TrackLowerBound));
                var target = _geometry.Clamp(
                    _geometry.TrackLowerBound
                    + (targetFraction * (_geometry.TrackUpperBound - _geometry.TrackLowerBound)));
                var agent = new PixelMovementAgent(member.Id, position, target);
                var node = new WorldNode(
                    member with { CharacterId = PixelCharacterCatalog.NormalizeId(member.CharacterId) },
                    agent);
                _nodeById.Add(member.Id, node);
                _nodes.Add(node);
                _agents.Add(agent);
                if (node.Member.Presence == PresenceState.Away)
                {
                    _dozeStartedAt[node.Member.Id] = _tick;
                }
            }
        }

        _stoppedIds.Clear();
        foreach (var node in _nodes)
        {
            if (node.Member.Presence is PresenceState.Away or PresenceState.Offline or PresenceState.Reconnecting)
            {
                _stoppedIds.Add(node.Member.Id);
            }
        }

        _bubbleBySender.Clear();
        var now = DateTimeOffset.UtcNow;
        foreach (var bubble in snapshot.Bubbles)
        {
            if (bubble.ExpiresAt > now)
            {
                _bubbleBySender[bubble.SenderId] = bubble;
            }
        }

        foreach (var pulse in snapshot.Pulses)
        {
            if (!_pulseReplayGuard.TryAccept(pulse))
            {
                continue;
            }

            _pulseStartedAt[pulse.UserId] = Stopwatch.GetTimestamp();
        }

        _textVisuals.Update(snapshot);
    }

    private int FrameIndex(
        PresenceState presence,
        bool moving,
        PixelCharacterFrameContract frames)
    {
        var range = presence switch
        {
            PresenceState.Away => frames.Doze,
            PresenceState.Offline => frames.Offline,
            _ when moving => frames.Walk,
            _ => frames.Idle,
        };
        var start = range.Start.Value;
        var count = range.End.Value - start;
        var divisor = moving ? 4L : 18L;
        return start + (int)((_tick / divisor) % count);
    }

    private double PulseScale(Guid userId)
    {
        if (!_pulseStartedAt.TryGetValue(userId, out var started))
        {
            return 1d;
        }

        var elapsed = Stopwatch.GetElapsedTime(started).TotalSeconds;
        if (elapsed <= 0.2d)
        {
            return 1d + (6d * elapsed / 0.2d);
        }

        if (elapsed <= 0.8d)
        {
            return 7d - (6d * (elapsed - 0.2d) / 0.6d);
        }

        _pulseStartedAt.Remove(userId);
        return 1d;
    }

    private (double X, double Y) FootPoint(double tangent) => _edge switch
    {
        OverlayEdge.Bottom => (
            _activityBounds.X + tangent,
            _activityBounds.Y + _activityBounds.Height - _edgeInsetPixels),
        OverlayEdge.Top => (
            _activityBounds.X + tangent,
            _activityBounds.Y + _edgeInsetPixels),
        OverlayEdge.Left => (
            _activityBounds.X + _edgeInsetPixels,
            _activityBounds.Y + tangent),
        OverlayEdge.Right => (
            _activityBounds.X + _activityBounds.Width - _edgeInsetPixels,
            _activityBounds.Y + tangent),
        _ => throw new ArgumentOutOfRangeException(),
    };

    private int ClampEdgeInset(int edgeInsetPixels)
    {
        var depth = _edge is OverlayEdge.Bottom or OverlayEdge.Top
            ? _activityBounds.Height
            : _activityBounds.Width;
        return Math.Clamp(edgeInsetPixels, 0, Math.Max(0, depth - 1));
    }

    private void AnimateEdgeInset()
    {
        var distance = _targetEdgeInsetPixels - _edgeInsetPixels;
        var maximumStep = EdgeInsetAnimationSpeedDipPerSecond
            * (_integerScale / 2d)
            * FixedDeltaTime;
        if (Math.Abs(distance) <= 1d)
        {
            _edgeInsetPixels = _targetEdgeInsetPixels;
            return;
        }

        var easedStep = Math.Clamp(Math.Abs(distance) * 0.24d, 1d, maximumStep);
        _edgeInsetPixels += Math.CopySign(easedStep, distance);
    }

    private (int X, int Y) DestinationForFoot(
        (double X, double Y) foot,
        int pixelSize,
        int baselinePixels,
        PixelContentBounds content,
        double pulseScale)
    {
        var scaledSize = pixelSize * pulseScale;
        var scaledBaseline = baselinePixels * pulseScale;
        var x = _edge switch
        {
            OverlayEdge.Left => foot.X - (content.MinX * pulseScale),
            OverlayEdge.Right => foot.X - (content.MaxX * pulseScale),
            _ => foot.X - (scaledSize / 2d),
        };
        var y = _edge switch
        {
            OverlayEdge.Top => foot.Y - scaledBaseline,
            OverlayEdge.Bottom => foot.Y - (scaledSize - scaledBaseline),
            _ => foot.Y - (scaledSize / 2d),
        };
        return (
            (int)Math.Round(x, MidpointRounding.AwayFromZero),
            (int)Math.Round(y, MidpointRounding.AwayFromZero));
    }

    private NativePixelRect HotspotBounds(
        (int X, int Y) sprite,
        int spriteSize,
        (double X, double Y) foot)
    {
        var centeredX = sprite.X + ((spriteSize - _hotspotPixelSize) / 2);
        var centeredY = sprite.Y + ((spriteSize - _hotspotPixelSize) / 2);
        var footX = (int)Math.Round(foot.X, MidpointRounding.AwayFromZero);
        var footY = (int)Math.Round(foot.Y, MidpointRounding.AwayFromZero);
        return _edge switch
        {
            OverlayEdge.Bottom => new NativePixelRect(
                centeredX,
                Math.Min(centeredY, footY - _hotspotPixelSize),
                _hotspotPixelSize,
                _hotspotPixelSize),
            OverlayEdge.Top => new NativePixelRect(
                centeredX,
                Math.Max(centeredY, footY),
                _hotspotPixelSize,
                _hotspotPixelSize),
            OverlayEdge.Left => new NativePixelRect(
                Math.Max(centeredX, footX),
                centeredY,
                _hotspotPixelSize,
                _hotspotPixelSize),
            OverlayEdge.Right => new NativePixelRect(
                Math.Min(centeredX, footX - _hotspotPixelSize),
                centeredY,
                _hotspotPixelSize,
                _hotspotPixelSize),
            _ => throw new ArgumentOutOfRangeException(),
        };
    }

    private void Composite(
        Span<byte> destination,
        ReadOnlySpan<byte> source,
        int sourceSize,
        int destinationX,
        int destinationY,
        double scale,
        double opacity,
        bool desaturate = false)
    {
        CompositeRectangle(
            destination,
            source,
            sourceSize,
            sourceSize,
            destinationX,
            destinationY,
            scale,
            opacity,
            desaturate);
    }

    private void CompositeVisual(
        Span<byte> destination,
        PremultipliedVisual visual,
        int destinationX,
        int destinationY,
        double opacity = 1d) =>
        CompositeRectangle(
            destination,
            visual.Pixels,
            visual.Width,
            visual.Height,
            destinationX - _renderBounds.X,
            destinationY - _renderBounds.Y,
            1d,
            opacity,
            desaturate: false);

    private void CompositeRectangle(
        Span<byte> destination,
        ReadOnlySpan<byte> source,
        int sourceWidth,
        int sourceHeight,
        int destinationX,
        int destinationY,
        double scale,
        double opacity,
        bool desaturate)
    {
        var destinationWidth = Math.Max(1, (int)Math.Round(sourceWidth * scale));
        var destinationHeight = Math.Max(1, (int)Math.Round(sourceHeight * scale));
        var useDirectColors = opacity >= 0.999d && !desaturate;
        for (var y = 0; y < destinationHeight; y++)
        {
            var worldY = destinationY + y;
            if (worldY < 0 || worldY >= _renderBounds.Height)
            {
                continue;
            }

            var sourceY = Math.Min(sourceHeight - 1, (int)(y / scale));
            for (var x = 0; x < destinationWidth; x++)
            {
                var worldX = destinationX + x;
                if (worldX < 0 || worldX >= _renderBounds.Width)
                {
                    continue;
                }

                var sourceX = Math.Min(sourceWidth - 1, (int)(x / scale));
                var sourceIndex = ((sourceY * sourceWidth) + sourceX) * 4;
                var sourceAlpha = useDirectColors
                    ? source[sourceIndex + 3]
                    : (byte)Math.Round(source[sourceIndex + 3] * opacity);
                if (sourceAlpha == 0)
                {
                    continue;
                }

                var destinationIndex = ((worldY * _renderBounds.Width) + worldX) * 4;
                var inverseAlpha = 255 - sourceAlpha;
                var sourceBlue = source[sourceIndex];
                var sourceGreen = source[sourceIndex + 1];
                var sourceRed = source[sourceIndex + 2];
                if (desaturate)
                {
                    var gray = (byte)((sourceBlue * 11 + sourceGreen * 59 + sourceRed * 30) / 100);
                    sourceBlue = (byte)((sourceBlue * 42 + gray * 58) / 100);
                    sourceGreen = (byte)((sourceGreen * 42 + gray * 58) / 100);
                    sourceRed = (byte)((sourceRed * 42 + gray * 58) / 100);
                }

                if (!useDirectColors)
                {
                    sourceBlue = (byte)Math.Round(sourceBlue * opacity);
                    sourceGreen = (byte)Math.Round(sourceGreen * opacity);
                    sourceRed = (byte)Math.Round(sourceRed * opacity);
                }

                destination[destinationIndex] = Blend(
                    sourceBlue,
                    destination[destinationIndex],
                    inverseAlpha);
                destination[destinationIndex + 1] = Blend(
                    sourceGreen,
                    destination[destinationIndex + 1],
                    inverseAlpha);
                destination[destinationIndex + 2] = Blend(
                    sourceRed,
                    destination[destinationIndex + 2],
                    inverseAlpha);
                destination[destinationIndex + 3] = Blend(
                    sourceAlpha,
                    destination[destinationIndex + 3],
                    inverseAlpha);
            }
        }
    }

    private (int X, int Y) PlaceNameplate(
        (int X, int Y) sprite,
        int spriteSize,
        PremultipliedVisual visual,
        PixelContentBounds content) => _edge switch
        {
            OverlayEdge.Bottom => (
                sprite.X + ((spriteSize - visual.Width) / 2),
                sprite.Y + content.MinY - NameplateCharacterGapPixels - visual.Height),
            OverlayEdge.Top => (
                sprite.X + ((spriteSize - visual.Width) / 2),
                sprite.Y + content.MaxY + NameplateCharacterGapPixels),
            OverlayEdge.Left => (
                sprite.X + content.MaxX + NameplateCharacterGapPixels,
                sprite.Y + ((spriteSize - visual.Height) / 2)),
            OverlayEdge.Right => (
                sprite.X + content.MinX - NameplateCharacterGapPixels - visual.Width,
                sprite.Y + ((spriteSize - visual.Height) / 2)),
            _ => throw new ArgumentOutOfRangeException(),
        };

    private (int X, int Y) PlaceBeyondNameplate(
        (int X, int Y) sprite,
        int spriteSize,
        PremultipliedVisual visual,
        int gap,
        PremultipliedVisual nameplate,
        (int X, int Y) nameplatePosition) => _edge switch
        {
            OverlayEdge.Bottom => (
                sprite.X + ((spriteSize - visual.Width) / 2),
                nameplatePosition.Y - gap - visual.Height),
            OverlayEdge.Top => (
                sprite.X + ((spriteSize - visual.Width) / 2),
                nameplatePosition.Y + nameplate.Height + gap),
            OverlayEdge.Left => (
                nameplatePosition.X + nameplate.Width + gap,
                sprite.Y + ((spriteSize - visual.Height) / 2)),
            OverlayEdge.Right => (
                nameplatePosition.X - gap - visual.Width,
                sprite.Y + ((spriteSize - visual.Height) / 2)),
            _ => throw new ArgumentOutOfRangeException(),
        };

    private (int X, int Y) PlaceDoze(
        (int X, int Y) sprite,
        int spriteSize,
        PremultipliedVisual visual) => _edge switch
        {
            OverlayEdge.Bottom => (sprite.X + spriteSize - (visual.Width / 3), sprite.Y - (visual.Height / 2)),
            OverlayEdge.Top => (sprite.X - (visual.Width / 2), sprite.Y + spriteSize - (visual.Height / 2)),
            OverlayEdge.Left => (sprite.X + spriteSize - (visual.Width / 2), sprite.Y + spriteSize - (visual.Height / 3)),
            OverlayEdge.Right => (sprite.X - (visual.Width / 2), sprite.Y - (visual.Height / 3)),
            _ => throw new ArgumentOutOfRangeException(),
        };

    private static double DozeAnimationProgress(long tick)
    {
        var phase = tick % FramesPerSecond;
        return phase <= FramesPerSecond / 2
            ? phase / (FramesPerSecond / 2d)
            : (FramesPerSecond - phase) / (FramesPerSecond / 2d);
    }

    private (int X, int Y) FloatDozeTowardInterior((int X, int Y) position, int distance) => _edge switch
    {
        OverlayEdge.Bottom => (position.X, position.Y - distance),
        OverlayEdge.Top => (position.X, position.Y + distance),
        OverlayEdge.Left => (position.X + distance, position.Y),
        OverlayEdge.Right => (position.X - distance, position.Y),
        _ => throw new ArgumentOutOfRangeException(),
    };

    private void MoveHotspotIfNeeded(NativePixelRect hotspot)
    {
        if (_lastHotspotBounds is { } previous
            && !HotspotTrackingPolicy.ShouldUpdate(
                Center(previous),
                Center(hotspot),
                TimeSpan.FromSeconds(_hotspotTrackingElapsed)))
        {
            return;
        }

        _hotspotMoved(hotspot);
        _lastHotspotBounds = hotspot;
        _hotspotTrackingElapsed = 0d;
    }

    private static byte Blend(byte source, byte destination, int inverseAlpha) =>
        (byte)Math.Min(255, source + ((destination * inverseAlpha + 127) / 255));

    private static PointD Center(NativePixelRect rect) =>
        new(rect.X + (rect.Width / 2d), rect.Y + (rect.Height / 2d));

    private static int DipToPixels(double value, uint dpi) =>
        (int)Math.Round(value * dpi / 96d, MidpointRounding.AwayFromZero);

    private sealed class WorldNode(PixelWorldMember member, PixelMovementAgent agent)
    {
        public PixelWorldMember Member { get; set; } = member;
        public PixelMovementAgent Agent { get; } = agent;
    }
}
