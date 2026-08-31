using Sidey.Core.Domain;
using Sidey.Core.Overlay;
using Sidey.Platform.Windows;

namespace Sidey.Overlay;

internal sealed class LayeredHamsterRenderer : IDisposable
{
    private const int FramesPerSecond = 30;
    private const int AuthoredFrameSize = 24;
    private const int AuthoredSheetWidth = 240;
    private const int BytesPerPixel = 4;
    private const double FixedDeltaTime = 1d / FramesPerSecond;
    private static readonly IReadOnlyList<RectD> NoAvoidanceRects = Array.Empty<RectD>();
    private static readonly IReadOnlySet<Guid> NoStoppedAgentIds = new HashSet<Guid>();

    private readonly object _gate = new();
    private readonly NativePixelRect _trackBounds;
    private readonly int _spritePixelSize;
    private readonly int _hotspotPixelSize;
    private readonly double _footInsetPixels;
    private readonly Action<NativePixelRect> _hotspotMoved;
    private readonly Random _random = new(0x51DE7);
    private readonly EdgeTrackGeometry _geometry;
    private readonly PixelMovementAgent _agent;
    private readonly PixelMovementAgent[] _agents;
    private readonly NativeLayeredBitmap[,] _frames;
    private readonly Timer _timer;
    private NativePixelRect? _lastHotspotBounds;
    private double _hotspotTrackingElapsed = double.PositiveInfinity;
    private long _tick;
    private bool _disposed;

    internal LayeredHamsterRenderer(
        nint windowHandle,
        NativePixelRect trackBounds,
        uint dpi,
        Action<NativePixelRect> hotspotMoved)
    {
        _trackBounds = trackBounds;
        _hotspotMoved = hotspotMoved;
        var scale = PixelScalePolicy.IntegerScale(dpi);
        _spritePixelSize = AuthoredFrameSize * scale;
        _hotspotPixelSize = Math.Max(1, DipToPixels(52, dpi));
        _footInsetPixels = EdgeTrackGeometry.FootInset * scale / 2d;
        _geometry = new EdgeTrackGeometry(
            new RectD(0, 0, trackBounds.Width, trackBounds.Height),
            OverlayEdge.Bottom);
        _agent = new PixelMovementAgent(
            Guid.Parse("51de7000-0000-0000-0000-000000000001"),
            _geometry.TangentLength / 2d,
            _geometry.TangentLength * 0.75d);
        _agents = [_agent];

        var rawPath = Path.Combine(
            AppContext.BaseDirectory,
            "Assets",
            "Characters",
            "pixel_hamster.bgra");
        var sheet = File.ReadAllBytes(rawPath);
        var expectedLength = AuthoredSheetWidth * AuthoredFrameSize * BytesPerPixel;
        if (sheet.Length != expectedLength)
        {
            throw new InvalidDataException(
                $"Hamster BGRA sheet must contain {expectedLength} bytes, found {sheet.Length}.");
        }

        _frames = new NativeLayeredBitmap[6, 2];
        try
        {
            for (var frame = 0; frame < _frames.GetLength(0); frame++)
            {
                _frames[frame, 0] = new NativeLayeredBitmap(
                    windowHandle,
                    _spritePixelSize,
                    _spritePixelSize,
                    BuildFrame(sheet, frame, scale, flipHorizontally: false));
                _frames[frame, 1] = new NativeLayeredBitmap(
                    windowHandle,
                    _spritePixelSize,
                    _spritePixelSize,
                    BuildFrame(sheet, frame, scale, flipHorizontally: true));
            }
        }
        catch
        {
            DisposeFrames();
            throw;
        }

        try
        {
            Present(frame: 0, flipHorizontally: false);
            _timer = new Timer(
                static state => ((LayeredHamsterRenderer)state!).Tick(),
                this,
                TimeSpan.FromSeconds(FixedDeltaTime),
                TimeSpan.FromSeconds(FixedDeltaTime));
        }
        catch
        {
            DisposeFrames();
            throw;
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
            DisposeFrames();
        }
    }

    private void Tick()
    {
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            if (Math.Abs(_agent.Target - _agent.TrackPosition) <= 2d)
            {
                var length = Math.Max(0d, _geometry.TrackUpperBound - _geometry.TrackLowerBound);
                _agent.Target = _geometry.TrackLowerBound + (_random.NextDouble() * length);
                _agent.IdleRemaining = 0.6d;
            }

            PixelMovementSimulation.Step(
                _agents,
                FixedDeltaTime,
                _geometry,
                NoAvoidanceRects,
                NoStoppedAgentIds);
            _tick++;
            _hotspotTrackingElapsed = Math.Min(
                1d,
                _hotspotTrackingElapsed + FixedDeltaTime);

            var moving = Math.Abs(_agent.Velocity) >= 0.5d;
            var frame = moving
                ? 2 + (int)((_tick / 4) % 4)
                : (int)((_tick / 18) % 2);
            Present(frame, _agent.Velocity < -0.1d);
        }
    }

    private void Present(int frame, bool flipHorizontally)
    {
        var anchorY = _trackBounds.Height - _footInsetPixels;
        var spriteX = _trackBounds.X + (int)Math.Round(
            _agent.TrackPosition - (_spritePixelSize / 2d),
            MidpointRounding.AwayFromZero);
        var spriteY = _trackBounds.Y + (int)Math.Round(
            anchorY - (_spritePixelSize / 2d),
            MidpointRounding.AwayFromZero);
        _frames[frame, flipHorizontally ? 1 : 0].Present(spriteX, spriteY);

        var hotspotBounds = new NativePixelRect(
            _trackBounds.X + (int)Math.Round(
                _agent.TrackPosition - (_hotspotPixelSize / 2d),
                MidpointRounding.AwayFromZero),
            _trackBounds.Y + (int)Math.Round(
                anchorY - (_hotspotPixelSize / 2d),
                MidpointRounding.AwayFromZero),
            _hotspotPixelSize,
            _hotspotPixelSize);
        if (_lastHotspotBounds is { } previous
            && !HotspotTrackingPolicy.ShouldUpdate(
                Center(previous),
                Center(hotspotBounds),
                TimeSpan.FromSeconds(_hotspotTrackingElapsed)))
        {
            return;
        }

        _hotspotMoved(hotspotBounds);
        _lastHotspotBounds = hotspotBounds;
        _hotspotTrackingElapsed = 0d;
    }

    private static byte[] BuildFrame(
        ReadOnlySpan<byte> sheet,
        int frame,
        int scale,
        bool flipHorizontally)
    {
        var outputSize = AuthoredFrameSize * scale;
        var output = new byte[checked(outputSize * outputSize * BytesPerPixel)];
        for (var outputY = 0; outputY < outputSize; outputY++)
        {
            var sourceY = outputY / scale;
            for (var outputX = 0; outputX < outputSize; outputX++)
            {
                var localSourceX = outputX / scale;
                if (flipHorizontally)
                {
                    localSourceX = AuthoredFrameSize - 1 - localSourceX;
                }

                var sourceX = (frame * AuthoredFrameSize) + localSourceX;
                var sourceIndex = ((sourceY * AuthoredSheetWidth) + sourceX) * BytesPerPixel;
                var outputIndex = ((outputY * outputSize) + outputX) * BytesPerPixel;
                var alpha = sheet[sourceIndex + 3];
                output[outputIndex] = Premultiply(sheet[sourceIndex], alpha);
                output[outputIndex + 1] = Premultiply(sheet[sourceIndex + 1], alpha);
                output[outputIndex + 2] = Premultiply(sheet[sourceIndex + 2], alpha);
                output[outputIndex + 3] = alpha;
            }
        }

        return output;
    }

    private void DisposeFrames()
    {
        foreach (var frame in _frames)
        {
            frame?.Dispose();
        }
    }

    private static byte Premultiply(byte color, byte alpha) =>
        (byte)(((color * alpha) + 127) / 255);

    private static PointD Center(NativePixelRect rect) =>
        new(rect.X + (rect.Width / 2d), rect.Y + (rect.Height / 2d));

    private static int DipToPixels(double value, uint dpi) =>
        (int)Math.Round(value * dpi / 96d, MidpointRounding.AwayFromZero);
}
