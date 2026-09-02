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
    private readonly Action? _hotspotDoubleClicked;
    private NativeOverlayWindow? _worldWindow;
    private NativeOverlayWindow? _hotspotWindow;
    private IDisposable? _threadResource;
    private ExceptionDispatchInfo? _startupFailure;
    private ExceptionDispatchInfo? _shutdownFailure;
    private bool _disposed;

    private NativeOverlayWindowThread(
        NativePixelRect initialWorldBounds,
        NativePixelRect initialHotspotBounds,
        Func<nint, IDisposable?>? initializeWorld,
        Action? hotspotActivated,
        Action? hotspotDoubleClicked)
    {
        _initialWorldBounds = initialWorldBounds;
        _initialHotspotBounds = initialHotspotBounds;
        _initializeWorld = initializeWorld;
        _hotspotActivated = hotspotActivated;
        _hotspotDoubleClicked = hotspotDoubleClicked;
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
        Action? hotspotActivated = null,
        Action? hotspotDoubleClicked = null)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The native overlay thread requires Windows.");
        }

        var owner = new NativeOverlayWindowThread(
            initialWorldBounds,
            initialHotspotBounds,
            initializeWorld,
            hotspotActivated,
            hotspotDoubleClicked);
        owner._thread.Start();
        if (!owner._started.Wait(StartupTimeout))
        {
            throw new TimeoutException("Timed out while creating SIDEY overlay windows.");
        }

        if (owner._startupFailure is { } startupFailure)
        {
            owner.Dispose();
            startupFailure.Throw();
        }

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

    public void EnsureTopmost()
    {
        RequiredWorldWindow.EnsureTopmost();
        RequiredHotspotWindow.EnsureTopmost();
    }

    public void YieldBehind(nint window)
    {
        RequiredWorldWindow.YieldBehind(window);
        RequiredHotspotWindow.YieldBehind(window);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        try
        {
            Interlocked.Exchange(ref _threadResource, null)?.Dispose();
        }
        catch (Exception exception)
        {
            _shutdownFailure = ExceptionDispatchInfo.Capture(exception);
        }

        _worldWindow?.Dispose();
        _hotspotWindow?.Dispose();
        if (_thread.IsAlive && !_thread.Join(ShutdownTimeout))
        {
            throw new TimeoutException("SIDEY overlay thread did not shut down within five seconds.");
        }

        _started.Dispose();
        _shutdownFailure?.Throw();
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
                _hotspotActivated,
                _hotspotDoubleClicked);
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
            try
            {
                Interlocked.Exchange(ref _threadResource, null)?.Dispose();
            }
            catch (Exception exception)
            {
                _shutdownFailure ??= ExceptionDispatchInfo.Capture(exception);
            }

            _worldWindow?.Dispose();
            _hotspotWindow?.Dispose();
        }
    }
}
