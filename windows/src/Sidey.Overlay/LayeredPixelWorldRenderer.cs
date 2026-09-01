using Sidey.Core.Domain;
using Sidey.Core.Overlay;
using Sidey.Platform.Windows;
using System.Diagnostics;

namespace Sidey.Overlay;

internal sealed class LayeredPixelWorldRenderer : IDisposable
{
    private const int FramesPerSecond = 30;
    private const double FixedDeltaTime = 1d / FramesPerSecond;
    private static readonly IReadOnlyList<RectD> NoAvoidanceRects = Array.Empty<RectD>();

    private readonly object _gate = new();
    private readonly NativePixelRect _activityBounds;
    private readonly NativePixelRect _renderBounds;
    private readonly int _hotspotPixelSize;
    private readonly int _integerScale;
    private readonly OverlayEdge _edge;
    private readonly Action<NativePixelRect> _hotspotMoved;
    private readonly Action<Exception> _renderingFailed;
    private readonly ValidationMetricsCollector? _metrics;
    private readonly Random _random;
    private readonly EdgeTrackGeometry _geometry;
    private readonly PixelCharacterFrameCache _frameCache;
    private readonly PixelTextVisualCache _textVisuals;
    private readonly NativeLayeredBitmap _surface;
    private readonly byte[] _worldPixels;
    private readonly List<WorldNode> _nodes = [];
    private readonly List<PixelMovementAgent> _agents = [];
    private readonly Dictionary<Guid, WorldNode> _nodeById = [];
    private readonly HashSet<Guid> _stoppedIds = [];
    private readonly Dictionary<Guid, long> _pulseStartedAt = [];
    private readonly Dictionary<Guid, ActiveBubble> _bubbleBySender = [];
    private readonly List<Guid> _expiredBubbleSenders = [];
    private readonly List<MessageBubbleTrackBounds> _bubbleTrackBounds = [];
    private readonly HashSet<Guid> _seenPulseIds = [];
    private readonly Queue<Guid> _seenPulseOrder = [];
    private readonly Timer _timer;
    private NativePixelRect? _lastHotspotBounds;
    private double _hotspotTrackingElapsed = double.PositiveInfinity;
    private long _tick;
    private int _tickRunning;
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
        ValidationMetricsCollector? metrics = null)
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
        _integerScale = PixelScalePolicy.IntegerScale(dpi);
        _hotspotPixelSize = Math.Max(1, DipToPixels(52, dpi));
        _random = new Random(unchecked((int)initialSnapshot.InstallationSeed));
        _geometry = new EdgeTrackGeometry(
            new RectD(0, 0, activityBounds.Width, activityBounds.Height),
            edge,
            Math.Max(24 * _integerScale, _hotspotPixelSize));
        var assetRoot = Path.Combine(AppContext.BaseDirectory, "Assets", "Characters");
        PixelCharacterFrameCache? frameCache = null;
        PixelTextVisualCache? textVisuals = null;
        NativeLayeredBitmap? surface = null;
        try
        {
            frameCache = new PixelCharacterFrameCache(
                assetRoot,
                _integerScale,
                edge,
                cachedCharacterIds);
            textVisuals = new PixelTextVisualCache(dpi);
            var worldPixels = new byte[checked(renderBounds.Width * renderBounds.Height * 4)];
            surface = new NativeLayeredBitmap(
                windowHandle,
                renderBounds.Width,
                renderBounds.Height,
                worldPixels);
            _frameCache = frameCache;
            _textVisuals = textVisuals;
            _worldPixels = worldPixels;
            _surface = surface;
            ApplySnapshotWithinGate(initialSnapshot);
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
            Array.Clear(_worldPixels);
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
                _stoppedIds);
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
                var estimatedWidthDip = Math.Clamp(24d + (bubble.Body.Length * 8d), 60d, 220d);
                var halfWidth = estimatedWidthDip * _integerScale / 4d;
                _bubbleTrackBounds.Add(new MessageBubbleTrackBounds(
                    bubble.SenderId,
                    node.Agent.TrackPosition - halfWidth,
                    node.Agent.TrackPosition + halfWidth));
            }
            MessageBubbleCollisionResolver.Apply(
                _agents,
                _bubbleTrackBounds,
                FixedDeltaTime,
                _geometry);
            _tick++;
            _hotspotTrackingElapsed = Math.Min(1d, _hotspotTrackingElapsed + FixedDeltaTime);
            RenderFrame();
        }
    }

    private void RenderFrame()
    {
        Array.Clear(_worldPixels);
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
                1d);
            var destination = DestinationForFoot(
                foot,
                cached.PixelSize,
                cached.Definition.FootBaselinePixel * _integerScale,
                pulseScale);
            Composite(
                cached.Frame(frame, node.Agent.Velocity < -0.1d),
                cached.PixelSize,
                destination.X - _renderBounds.X,
                destination.Y - _renderBounds.Y,
                pulseScale,
                node.Member.Presence == PresenceState.Offline ? 0.75d : 1d,
                desaturate: node.Member.Presence == PresenceState.Offline);

            if (node.Member.IsCurrentUser)
            {
                currentUserHotspot = new NativePixelRect(
                    baseDestination.X + ((cached.PixelSize - _hotspotPixelSize) / 2),
                    baseDestination.Y + ((cached.PixelSize - _hotspotPixelSize) / 2),
                    _hotspotPixelSize,
                    _hotspotPixelSize);
            }

            var visuals = _textVisuals.Get(node.Member.Id);
            var nameplate = PlaceInward(
                baseDestination,
                cached.PixelSize,
                visuals.Nameplate,
                gap: 4,
                priorVisual: null);
            CompositeVisual(visuals.Nameplate, nameplate.X, nameplate.Y);
            var bubble = _bubbleBySender.ContainsKey(node.Member.Id)
                ? visuals.MessageBubble
                : visuals.TypingBubble;
            if (bubble is not null)
            {
                var bubblePosition = PlaceInward(
                    baseDestination,
                    cached.PixelSize,
                    bubble,
                    gap: 4,
                    priorVisual: visuals.Nameplate);
                CompositeVisual(bubble, bubblePosition.X, bubblePosition.Y);
            }
            if (visuals.Doze is { } doze)
            {
                var dozePosition = PlaceDoze(baseDestination, cached.PixelSize, doze);
                var wave = (Math.Sin(_tick / 8d) + 1d) / 2d;
                CompositeVisual(
                    doze,
                    dozePosition.X,
                    dozePosition.Y - (int)Math.Round(wave * _integerScale),
                    0.6d + (wave * 0.35d));
            }
        }

        _surface.UpdatePixels(_worldPixels);
        _surface.Present(_renderBounds.X, _renderBounds.Y);
        if (currentUserHotspot is { } hotspot)
        {
            MoveHotspotIfNeeded(hotspot);
        }
    }

    private void ApplySnapshotWithinGate(WorldSnapshot snapshot)
    {
        var incoming = snapshot.Members.Select(member => member.Id).ToHashSet();
        for (var index = _nodes.Count - 1; index >= 0; index--)
        {
            var node = _nodes[index];
            if (incoming.Contains(node.Member.Id))
            {
                continue;
            }

            _nodes.RemoveAt(index);
            _agents.Remove(node.Agent);
            _nodeById.Remove(node.Member.Id);
            _stoppedIds.Remove(node.Member.Id);
            _pulseStartedAt.Remove(node.Member.Id);
        }

        foreach (var member in snapshot.Members)
        {
            if (_nodeById.TryGetValue(member.Id, out var existing))
            {
                existing.Member = member with
                {
                    CharacterId = PixelCharacterCatalog.NormalizeId(member.CharacterId),
                };
            }
            else
            {
                var fraction = StableFraction(member.Id, snapshot.InstallationSeed);
                var position = _geometry.TrackLowerBound
                    + (fraction * (_geometry.TrackUpperBound - _geometry.TrackLowerBound));
                var target = _geometry.Clamp(
                    _geometry.TrackLowerBound
                    + ((1d - fraction) * (_geometry.TrackUpperBound - _geometry.TrackLowerBound)));
                var agent = new PixelMovementAgent(member.Id, position, target);
                var node = new WorldNode(
                    member with { CharacterId = PixelCharacterCatalog.NormalizeId(member.CharacterId) },
                    agent);
                _nodeById.Add(member.Id, node);
                _nodes.Add(node);
                _agents.Add(agent);
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
        foreach (var bubble in snapshot.Bubbles.Where(bubble => bubble.ExpiresAt > DateTimeOffset.UtcNow))
        {
            _bubbleBySender[bubble.SenderId] = bubble;
        }

        foreach (var pulse in snapshot.Pulses)
        {
            if (!_seenPulseIds.Add(pulse.Id))
            {
                continue;
            }

            _seenPulseOrder.Enqueue(pulse.Id);
            _pulseStartedAt[pulse.UserId] = Stopwatch.GetTimestamp();
            while (_seenPulseOrder.Count > 256)
            {
                _seenPulseIds.Remove(_seenPulseOrder.Dequeue());
            }
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
        OverlayEdge.Bottom => (_activityBounds.X + tangent, _activityBounds.Y + _activityBounds.Height),
        OverlayEdge.Top => (_activityBounds.X + tangent, _activityBounds.Y),
        OverlayEdge.Left => (_activityBounds.X, _activityBounds.Y + tangent),
        OverlayEdge.Right => (_activityBounds.X + _activityBounds.Width, _activityBounds.Y + tangent),
        _ => throw new ArgumentOutOfRangeException(),
    };

    private (int X, int Y) DestinationForFoot(
        (double X, double Y) foot,
        int pixelSize,
        int baselinePixels,
        double pulseScale)
    {
        var scaledSize = pixelSize * pulseScale;
        var scaledBaseline = baselinePixels * pulseScale;
        var x = _edge switch
        {
            OverlayEdge.Left => foot.X - scaledBaseline,
            OverlayEdge.Right => foot.X - (scaledSize - scaledBaseline),
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

    private void Composite(
        ReadOnlySpan<byte> source,
        int sourceSize,
        int destinationX,
        int destinationY,
        double scale,
        double opacity,
        bool desaturate = false)
    {
        CompositeRectangle(
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
        PremultipliedVisual visual,
        int destinationX,
        int destinationY,
        double opacity = 1d) =>
        CompositeRectangle(
            visual.Pixels,
            visual.Width,
            visual.Height,
            destinationX - _renderBounds.X,
            destinationY - _renderBounds.Y,
            1d,
            opacity,
            desaturate: false);

    private void CompositeRectangle(
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
                var sourceAlpha = (byte)Math.Round(source[sourceIndex + 3] * opacity);
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

                _worldPixels[destinationIndex] = Blend(
                    (byte)Math.Round(sourceBlue * opacity),
                    _worldPixels[destinationIndex],
                    inverseAlpha);
                _worldPixels[destinationIndex + 1] = Blend(
                    (byte)Math.Round(sourceGreen * opacity),
                    _worldPixels[destinationIndex + 1],
                    inverseAlpha);
                _worldPixels[destinationIndex + 2] = Blend(
                    (byte)Math.Round(sourceRed * opacity),
                    _worldPixels[destinationIndex + 2],
                    inverseAlpha);
                _worldPixels[destinationIndex + 3] = Blend(
                    sourceAlpha,
                    _worldPixels[destinationIndex + 3],
                    inverseAlpha);
            }
        }
    }

    private (int X, int Y) PlaceInward(
        (int X, int Y) sprite,
        int spriteSize,
        PremultipliedVisual visual,
        int gap,
        PremultipliedVisual? priorVisual)
    {
        var additional = priorVisual is null
            ? 0
            : gap + (_edge is OverlayEdge.Bottom or OverlayEdge.Top
                ? priorVisual.Height
                : priorVisual.Width);
        return _edge switch
        {
            OverlayEdge.Bottom => (
                sprite.X + ((spriteSize - visual.Width) / 2),
                sprite.Y - gap - visual.Height - additional),
            OverlayEdge.Top => (
                sprite.X + ((spriteSize - visual.Width) / 2),
                sprite.Y + spriteSize + gap + additional),
            OverlayEdge.Left => (
                sprite.X + spriteSize + gap + additional,
                sprite.Y + ((spriteSize - visual.Height) / 2)),
            OverlayEdge.Right => (
                sprite.X - gap - visual.Width - additional,
                sprite.Y + ((spriteSize - visual.Height) / 2)),
            _ => throw new ArgumentOutOfRangeException(),
        };
    }

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

    private static double StableFraction(Guid id, long seed)
    {
        var bytes = id.ToByteArray();
        var value = BitConverter.ToUInt64(bytes, 0) ^ BitConverter.ToUInt64(bytes, 8) ^ unchecked((ulong)seed);
        value ^= value >> 33;
        value *= 0xff51afd7ed558ccdUL;
        value ^= value >> 33;
        return (value & 0x1FFFFFFFFFFFFFUL) / (double)0x20000000000000UL;
    }

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
