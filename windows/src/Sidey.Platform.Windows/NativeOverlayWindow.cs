using System.Collections.Concurrent;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.UI.WindowsAndMessaging;

namespace Sidey.Platform.Windows;

public enum NativeOverlayWindowRole
{
    World,
    Hotspot,
}

public readonly record struct NativePixelRect(int X, int Y, int Width, int Height)
{
    public bool IsValid => Width > 0 && Height > 0;
}

public sealed unsafe class NativeOverlayWindow : IDisposable
{
    private const string WindowClassName = "SIDEY.NativeOverlayWindow";
    private const byte AlmostTransparent = 1;
    private static readonly object RegistrationLock = new();
    private static readonly ConcurrentDictionary<nint, NativeOverlayWindowRole> Roles = new();
    private static readonly ConcurrentDictionary<nint, Action> Activations = new();
    private static readonly ConcurrentDictionary<nint, Action> DoubleClickActivations = new();
    private static readonly ConcurrentDictionary<nint, uint> OwnerThreads = new();
    private static readonly ConcurrentDictionary<uint, int> ThreadWindowCounts = new();
    private static readonly WNDPROC WindowProcedureCallback = WindowProcedure;
    private static readonly HWND TopmostWindow = new((void*)(-1));
    private static readonly HWND NotTopmostWindow = new((void*)(-2));
    private static bool _classRegistered;

    private HWND _handle;
    private readonly uint _ownerThreadId;
    private nint _yieldBehindWindow;
    private bool _isTopmost = true;
    private bool _disposed;

    private NativeOverlayWindow(
        HWND handle,
        NativeOverlayWindowRole role,
        Action? activated,
        Action? doubleClicked)
    {
        _handle = handle;
        Role = role;
        var handleValue = (nint)handle.Value;
        var ownerThread = PInvoke.GetCurrentThreadId();
        _ownerThreadId = ownerThread;
        Roles[handleValue] = role;
        if (activated is not null)
        {
            Activations[handleValue] = activated;
        }
        if (doubleClicked is not null)
        {
            DoubleClickActivations[handleValue] = doubleClicked;
        }
        OwnerThreads[handleValue] = ownerThread;
        ThreadWindowCounts.AddOrUpdate(ownerThread, 1, static (_, count) => count + 1);
    }

    public NativeOverlayWindowRole Role { get; }
    public nint Handle => (nint)_handle.Value;
    public bool IsCreated => _handle != HWND.Null;

    public static uint ExtendedStyleBits(NativeOverlayWindowRole role) =>
        (uint)WindowStyles.ExtendedStyle(role);

    public static unsafe NativeOverlayWindow Create(
        NativeOverlayWindowRole role,
        NativePixelRect initialBounds,
        Action? activated = null,
        Action? doubleClicked = null)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("NativeOverlayWindow requires Windows.");
        }

        if (!initialBounds.IsValid)
        {
            throw new ArgumentOutOfRangeException(nameof(initialBounds));
        }

        EnsureWindowClass();
        var module = PInvoke.GetModuleHandle((string?)null);
        var extendedStyle = WindowStyles.ExtendedStyle(role);
        var handle = PInvoke.CreateWindowEx(
            extendedStyle,
            WindowClassName,
            "SIDEY Overlay",
            WINDOW_STYLE.WS_POPUP,
            initialBounds.X,
            initialBounds.Y,
            initialBounds.Width,
            initialBounds.Height,
            HWND.Null,
            new FreeLibrarySafeHandle(),
            module,
            null);

        if (handle == HWND.Null)
        {
            throw new Win32Exception(Marshal.GetLastPInvokeError(), "CreateWindowExW failed.");
        }

        if (role == NativeOverlayWindowRole.Hotspot
            && !PInvoke.SetLayeredWindowAttributes(
                handle,
                default,
                AlmostTransparent,
                LAYERED_WINDOW_ATTRIBUTES_FLAGS.LWA_ALPHA))
        {
            PInvoke.DestroyWindow(handle);
            throw new Win32Exception(Marshal.GetLastPInvokeError(), "SetLayeredWindowAttributes failed.");
        }

        var window = new NativeOverlayWindow(handle, role, activated, doubleClicked);
        window.SetBounds(initialBounds, visible: true);
        return window;
    }

    public void SetBounds(NativePixelRect bounds, bool visible)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (!bounds.IsValid)
        {
            throw new ArgumentOutOfRangeException(nameof(bounds));
        }

        var flags = SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE | SET_WINDOW_POS_FLAGS.SWP_NOOWNERZORDER;
        flags |= visible ? SET_WINDOW_POS_FLAGS.SWP_SHOWWINDOW : SET_WINDOW_POS_FLAGS.SWP_HIDEWINDOW;
        if (!PInvoke.SetWindowPos(
                _handle,
                ZOrderAnchor(),
                bounds.X,
                bounds.Y,
                bounds.Width,
                bounds.Height,
                flags))
        {
            throw new Win32Exception(Marshal.GetLastPInvokeError(), "SetWindowPos failed.");
        }
    }

    public void SetVisible(bool visible)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (!visible)
        {
            PInvoke.ShowWindow(_handle, SHOW_WINDOW_CMD.SW_HIDE);
            return;
        }

        ApplyZOrder(SET_WINDOW_POS_FLAGS.SWP_SHOWWINDOW);
    }

    public void EnsureTopmost()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        _isTopmost = true;
        _yieldBehindWindow = nint.Zero;
        ApplyZOrder(default);
    }

    public void YieldBehind(nint window)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        _isTopmost = false;
        _yieldBehindWindow = window;
        ApplyZOrder(default);
    }

    private void ApplyZOrder(SET_WINDOW_POS_FLAGS additionalFlags)
    {
        var flags = SET_WINDOW_POS_FLAGS.SWP_NOMOVE
            | SET_WINDOW_POS_FLAGS.SWP_NOSIZE
            | SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE
            | SET_WINDOW_POS_FLAGS.SWP_NOOWNERZORDER
            | additionalFlags;
        if (!PInvoke.SetWindowPos(_handle, ZOrderAnchor(), 0, 0, 0, 0, flags))
        {
            throw new Win32Exception(Marshal.GetLastPInvokeError(), "SetWindowPos failed while updating overlay Z-order.");
        }
    }

    private HWND ZOrderAnchor()
    {
        if (_isTopmost)
        {
            return TopmostWindow;
        }

        var yieldWindow = new HWND((void*)_yieldBehindWindow);
        return yieldWindow != HWND.Null && NativeMethods.IsWindow(_yieldBehindWindow)
            ? yieldWindow
            : NotTopmostWindow;
    }

    private static class NativeMethods
    {
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsWindow(nint window);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        var handle = _handle;
        _handle = HWND.Null;
        if (handle != HWND.Null)
        {
            Roles.TryRemove((nint)handle.Value, out _);
            Activations.TryRemove((nint)handle.Value, out _);
            DoubleClickActivations.TryRemove((nint)handle.Value, out _);
            if (PInvoke.GetCurrentThreadId() == _ownerThreadId)
            {
                PInvoke.DestroyWindow(handle);
            }
            else
            {
                PInvoke.PostMessage(handle, PInvoke.WM_CLOSE, default, default);
            }
        }
    }

    private static unsafe void EnsureWindowClass()
    {
        lock (RegistrationLock)
        {
            if (_classRegistered)
            {
                return;
            }

            var module = PInvoke.GetModuleHandle((string?)null);
            fixed (char* className = WindowClassName)
            {
                var windowClass = new WNDCLASSW
                {
                    style = (WNDCLASS_STYLES)0x0008, // CS_DBLCLKS
                    lpfnWndProc = WindowProcedureCallback,
                    hInstance = new HINSTANCE(module.DangerousGetHandle()),
                    hCursor = PInvoke.LoadCursor(HINSTANCE.Null, PInvoke.IDC_ARROW),
                    lpszClassName = new PCWSTR(className),
                };

                if (PInvoke.RegisterClass(windowClass) == 0)
                {
                    throw new Win32Exception(Marshal.GetLastPInvokeError(), "RegisterClassW failed.");
                }
            }

            _classRegistered = true;
        }
    }

    private static LRESULT WindowProcedure(HWND window, uint message, WPARAM wParam, LPARAM lParam)
    {
        if (message == PInvoke.WM_NCHITTEST
            && Roles.TryGetValue((nint)window.Value, out var role)
            && role == NativeOverlayWindowRole.World)
        {
            return new LRESULT(-1); // HTTRANSPARENT is defense-in-depth; WS_EX_LAYERED | WS_EX_TRANSPARENT owns cross-process pass-through.
        }

        if (message == PInvoke.WM_MOUSEACTIVATE)
        {
            return new LRESULT(3); // MA_NOACTIVATE
        }

        if (message == PInvoke.WM_LBUTTONUP
            && Activations.TryGetValue((nint)window.Value, out var activated))
        {
            try
            {
                activated();
            }
            catch (Exception exception)
            {
                Trace.TraceError("SIDEY hotspot callback failed: {0}", exception);
            }

            return default;
        }

        if (message == 0x0203 // WM_LBUTTONDBLCLK
            && DoubleClickActivations.TryGetValue((nint)window.Value, out var doubleClicked))
        {
            try
            {
                doubleClicked();
            }
            catch (Exception exception)
            {
                Trace.TraceError("SIDEY hotspot double-click callback failed: {0}", exception);
            }

            return default;
        }

        if (message == PInvoke.WM_CLOSE)
        {
            PInvoke.DestroyWindow(window);
            return default;
        }

        if (message == PInvoke.WM_DESTROY)
        {
            var handle = (nint)window.Value;
            Roles.TryRemove(handle, out _);
            Activations.TryRemove(handle, out _);
            DoubleClickActivations.TryRemove(handle, out _);
            if (OwnerThreads.TryRemove(handle, out var ownerThread))
            {
                var remaining = ThreadWindowCounts.AddOrUpdate(
                    ownerThread,
                    0,
                    static (_, count) => Math.Max(0, count - 1));
                if (remaining == 0)
                {
                    ThreadWindowCounts.TryRemove(ownerThread, out _);
                    PInvoke.PostQuitMessage(0);
                }
            }
            return default;
        }

        return PInvoke.DefWindowProc(window, message, wParam, lParam);
    }
}

internal static class WindowStyles
{
    internal static WINDOW_EX_STYLE ExtendedStyle(NativeOverlayWindowRole role)
    {
        var style = WINDOW_EX_STYLE.WS_EX_TOPMOST
            | WINDOW_EX_STYLE.WS_EX_TOOLWINDOW
            | WINDOW_EX_STYLE.WS_EX_NOACTIVATE
            | WINDOW_EX_STYLE.WS_EX_LAYERED;
        return role == NativeOverlayWindowRole.World
            ? style | WINDOW_EX_STYLE.WS_EX_TRANSPARENT
            : style;
    }
}
