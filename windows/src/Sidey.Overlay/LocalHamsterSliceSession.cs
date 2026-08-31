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

    public static LocalHamsterSliceSession Start(
        Core.Domain.OverlayRegionPreference preference,
        Action requestComposer,
        Action<Exception> renderingFailed)
    {
        ArgumentNullException.ThrowIfNull(requestComposer);
        ArgumentNullException.ThrowIfNull(renderingFailed);
        var monitor = PrimaryMonitorService.GetPrimary();
        var work = monitor.WorkAreaPixels;
        var world = WindowsOverlayRegionLayout.Frame(work, monitor.Dpi, preference);
        var dipScale = monitor.Dpi / 96d;
        var hotspotSize = Math.Max(
            1,
            (int)Math.Round(52d * dipScale, MidpointRounding.AwayFromZero));
        var hotspot = InitialBounds(world, monitor.Dpi, preference.Edge, hotspotSize);

        NativeOverlayWindowThread? windows = null;
        windows = NativeOverlayWindowThread.Start(
            InitialBounds(world, monitor.Dpi, preference.Edge, sizeOverride: null),
            hotspot,
            handle => new LayeredHamsterRenderer(
                handle,
                world,
                monitor.Dpi,
                preference.Edge,
                bounds => windows?.SetHotspotBounds(bounds),
                renderingFailed),
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

    private static NativePixelRect InitialBounds(
        NativePixelRect world,
        uint dpi,
        Core.Domain.OverlayEdge edge,
        int? sizeOverride)
    {
        var scale = Core.Overlay.PixelScalePolicy.IntegerScale(dpi);
        var size = sizeOverride ?? 24 * scale;
        var footInset = Core.Overlay.EdgeTrackGeometry.FootInset * scale / 2d;
        var tangent = edge is Core.Domain.OverlayEdge.Bottom or Core.Domain.OverlayEdge.Top
            ? world.Width / 2d
            : world.Height / 2d;
        var (anchorX, anchorY) = Anchor(world, edge, tangent, footInset);
        return new NativePixelRect(
            (int)Math.Round(anchorX - (size / 2d), MidpointRounding.AwayFromZero),
            (int)Math.Round(anchorY - (size / 2d), MidpointRounding.AwayFromZero),
            size,
            size);
    }

    private static (double X, double Y) Anchor(
        NativePixelRect world,
        Core.Domain.OverlayEdge edge,
        double tangent,
        double footInset) => edge switch
    {
        Core.Domain.OverlayEdge.Bottom => (world.X + tangent, world.Y + world.Height - footInset),
        Core.Domain.OverlayEdge.Top => (world.X + tangent, world.Y + footInset),
        Core.Domain.OverlayEdge.Left => (world.X + footInset, world.Y + tangent),
        Core.Domain.OverlayEdge.Right => (world.X + world.Width - footInset, world.Y + tangent),
        _ => throw new ArgumentOutOfRangeException(nameof(edge)),
    };
}
