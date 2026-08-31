using Sidey.Platform.Windows;

namespace Sidey.Overlay;

public sealed class LocalHamsterSliceSession : IDisposable
{
    private readonly NativeOverlayWindowThread _windows;
    private bool _disposed;

    private LocalHamsterSliceSession(NativeOverlayWindowThread windows)
    {
        _windows = windows;
    }

    public static LocalHamsterSliceSession Start(Action requestComposer)
    {
        ArgumentNullException.ThrowIfNull(requestComposer);
        var monitor = PrimaryMonitorService.GetPrimary();
        var work = monitor.WorkAreaPixels;
        var dipScale = monitor.Dpi / 96d;
        var preferredDepth = (int)Math.Round(240d * dipScale, MidpointRounding.AwayFromZero);
        var depth = Math.Min(preferredDepth, work.Height / 3);
        var world = new NativePixelRect(
            work.X,
            work.Y + work.Height - depth,
            work.Width,
            depth);
        var hotspotSize = Math.Max(
            1,
            (int)Math.Round(52d * dipScale, MidpointRounding.AwayFromZero));
        var hotspot = new NativePixelRect(
            world.X + ((world.Width - hotspotSize) / 2),
            work.Y + work.Height - hotspotSize,
            hotspotSize,
            hotspotSize);

        NativeOverlayWindowThread? windows = null;
        windows = NativeOverlayWindowThread.Start(
            InitialSpriteBounds(world, monitor.Dpi),
            hotspot,
            handle => new LayeredHamsterRenderer(
                handle,
                world,
                monitor.Dpi,
                bounds => windows?.SetHotspotBounds(bounds)),
            requestComposer);
        return new LocalHamsterSliceSession(windows);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _windows.Dispose();
    }

    private static NativePixelRect InitialSpriteBounds(NativePixelRect world, uint dpi)
    {
        var scale = Core.Overlay.PixelScalePolicy.IntegerScale(dpi);
        var size = 24 * scale;
        return new NativePixelRect(
            world.X + ((world.Width - size) / 2),
            world.Y + world.Height - size,
            size,
            size);
    }
}
