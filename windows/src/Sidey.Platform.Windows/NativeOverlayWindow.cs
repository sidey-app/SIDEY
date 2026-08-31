using System.ComponentModel;
using System.Collections.Concurrent;
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
    private const byte FullyOpaque = 255;
    private static readonly object RegistrationLock = new();
    private static readonly ConcurrentDictionary<nint, NativeOverlayWindowRole> Roles = new();
    private static readonly WNDPROC WindowProcedureCallback = WindowProcedure;
    private static readonly HWND TopmostWindow = new((void*)(-1));
    private static bool _classRegistered;

    private HWND _handle;
    private bool _disposed;

    private NativeOverlayWindow(HWND handle, NativeOverlayWindowRole role)
    {
        _handle = handle;
        Role = role;
        Roles[(nint)handle.Value] = role;
    }

    public NativeOverlayWindowRole Role { get; }
    public nint Handle => (nint)_handle.Value;
    public bool IsCreated => _handle != HWND.Null;

    public static unsafe NativeOverlayWindow Create(
        NativeOverlayWindowRole role,
        NativePixelRect initialBounds)
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

        if (!PInvoke.SetLayeredWindowAttributes(
                handle,
                default,
                FullyOpaque,
                LAYERED_WINDOW_ATTRIBUTES_FLAGS.LWA_ALPHA))
        {
            PInvoke.DestroyWindow(handle);
            throw new Win32Exception(Marshal.GetLastPInvokeError(), "SetLayeredWindowAttributes failed.");
        }

        var window = new NativeOverlayWindow(handle, role);
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
                TopmostWindow,
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
        PInvoke.ShowWindow(_handle, visible ? SHOW_WINDOW_CMD.SW_SHOWNOACTIVATE : SHOW_WINDOW_CMD.SW_HIDE);
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
            PInvoke.PostMessage(handle, PInvoke.WM_CLOSE, default, default);
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

        if (message == PInvoke.WM_CLOSE)
        {
            PInvoke.DestroyWindow(window);
            return default;
        }

        if (message == PInvoke.WM_DESTROY)
        {
            Roles.TryRemove((nint)window.Value, out _);
            PInvoke.PostQuitMessage(0);
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
            | WINDOW_EX_STYLE.WS_EX_LAYERED
            | WINDOW_EX_STYLE.WS_EX_NOREDIRECTIONBITMAP;
        return role == NativeOverlayWindowRole.World
            ? style | WINDOW_EX_STYLE.WS_EX_TRANSPARENT
            : style;
    }
}
