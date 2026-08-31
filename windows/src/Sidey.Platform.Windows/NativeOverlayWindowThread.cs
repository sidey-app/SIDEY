using System.Runtime.ExceptionServices;

namespace Sidey.Platform.Windows;

public sealed class NativeOverlayWindowThread : IDisposable
{
    private static readonly TimeSpan StartupTimeout = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan ShutdownTimeout = TimeSpan.FromSeconds(5);

    private readonly NativePixelRect _initialWorldBounds;
    private readonly NativePixelRect _initialHotspotBounds;
    private readonly ManualResetEventSlim _started = new(false);
    private readonly Thread _thread;
    private readonly Func<nint, IDisposable?>? _initializeWorld;
    private readonly Action? _hotspotActivated;
    private NativeOverlayWindow? _worldWindow;
    private NativeOverlayWindow? _hotspotWindow;
    private IDisposable? _threadResource;
    private ExceptionDispatchInfo? _startupFailure;
    private bool _disposed;

    private NativeOverlayWindowThread(
        NativePixelRect initialWorldBounds,
        NativePixelRect initialHotspotBounds,
        Func<nint, IDisposable?>? initializeWorld,
        Action? hotspotActivated)
    {
        _initialWorldBounds = initialWorldBounds;
        _initialHotspotBounds = initialHotspotBounds;
        _initializeWorld = initializeWorld;
        _hotspotActivated = hotspotActivated;
        _thread = new Thread(Run)
        {
            IsBackground = true,
            Name = "SIDEY Overlay",
        };
        _thread.SetApartmentState(ApartmentState.STA);
    }

    public nint WorldWindowHandle => RequiredWorldWindow.Handle;
    public nint HotspotWindowHandle => RequiredHotspotWindow.Handle;

    public static NativeOverlayWindowThread Start(
        NativePixelRect initialWorldBounds,
        NativePixelRect initialHotspotBounds,
        Func<nint, IDisposable?>? initializeWorld = null,
        Action? hotspotActivated = null)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The native overlay thread requires Windows.");
        }

        var owner = new NativeOverlayWindowThread(
            initialWorldBounds,
            initialHotspotBounds,
            initializeWorld,
            hotspotActivated);
        owner._thread.Start();
        if (!owner._started.Wait(StartupTimeout))
        {
            throw new TimeoutException("Timed out while creating SIDEY overlay windows.");
        }

        owner._startupFailure?.Throw();
        return owner;
    }

    public void SetWorldBounds(NativePixelRect bounds, bool visible = true) =>
        RequiredWorldWindow.SetBounds(bounds, visible);

    public void SetHotspotBounds(NativePixelRect bounds, bool visible = true) =>
        RequiredHotspotWindow.SetBounds(bounds, visible);

    public void SetVisible(bool visible)
    {
        RequiredWorldWindow.SetVisible(visible);
        RequiredHotspotWindow.SetVisible(visible);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _worldWindow?.Dispose();
        _hotspotWindow?.Dispose();
        if (_thread.IsAlive && !_thread.Join(ShutdownTimeout))
        {
            throw new TimeoutException("SIDEY overlay thread did not shut down within five seconds.");
        }

        _started.Dispose();
    }

    private NativeOverlayWindow RequiredWorldWindow =>
        _worldWindow ?? throw new InvalidOperationException("World overlay window is not available.");

    private NativeOverlayWindow RequiredHotspotWindow =>
        _hotspotWindow ?? throw new InvalidOperationException("Hotspot window is not available.");

    private void Run()
    {
        try
        {
            _worldWindow = NativeOverlayWindow.Create(NativeOverlayWindowRole.World, _initialWorldBounds);
            _hotspotWindow = NativeOverlayWindow.Create(
                NativeOverlayWindowRole.Hotspot,
                _initialHotspotBounds,
                _hotspotActivated);
            _threadResource = _initializeWorld?.Invoke(_worldWindow.Handle);
            _started.Set();
            NativeMessageLoop.Run();
        }
        catch (Exception exception)
        {
            _startupFailure = ExceptionDispatchInfo.Capture(exception);
            _started.Set();
        }
        finally
        {
            _threadResource?.Dispose();
            _worldWindow?.Dispose();
            _hotspotWindow?.Dispose();
        }
    }
}
