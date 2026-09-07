using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Sidey.Platform.Windows;

// Keep the native window/presenter intact and remove only its non-client area.
// Attach and dispose on the window's owning UI thread.
public sealed class WindowsBorderlessWindowController : IDisposable
{
    private const nuint SubclassId = 0x5349424C;
    private readonly WindowSubclassProcedure _windowProcedure;
    private nint _windowHandle;

    public WindowsBorderlessWindowController(nint windowHandle)
    {
        if (windowHandle == nint.Zero)
        {
            throw new ArgumentException("A valid window handle is required.", nameof(windowHandle));
        }

        _windowHandle = windowHandle;
        _windowProcedure = WindowProcedure;
        if (!SetWindowSubclass(windowHandle, _windowProcedure, SubclassId, 0))
        {
            _windowHandle = nint.Zero;
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        // SWP_FRAMECHANGED | NOMOVE | NOSIZE | NOZORDER | NOACTIVATE.
        if (!SetWindowPos(windowHandle, 0, 0, 0, 0, 0, 0x0037))
        {
            int error = Marshal.GetLastWin32Error();
            Dispose();
            throw new Win32Exception(error);
        }

        // A fully client-drawn window no longer qualifies for automatic rounding.
        // Opt into DWM's smooth outer corners without changing the presenter.
        int cornerPreference = 2; // DWMWCP_ROUND
        _ = DwmSetWindowAttribute(windowHandle, 33, ref cornerPreference, sizeof(int));
    }

    public void Dispose()
    {
        if (_windowHandle != nint.Zero)
        {
            _ = RemoveWindowSubclass(_windowHandle, _windowProcedure, SubclassId);
            _windowHandle = nint.Zero;
        }

        GC.KeepAlive(_windowProcedure);
    }

    private nint WindowProcedure(
        nint window,
        uint message,
        nuint wParam,
        nint lParam,
        nuint subclassId,
        nuint referenceData)
    {
        switch (message)
        {
            case 0x0083: // WM_NCCALCSIZE: retain the full proposed window rectangle.
                return 0;
            case 0x0084: // WM_NCHITTEST: no invisible caption buttons or resize edges.
                return 1; // HTCLIENT
            case 0x0082: // WM_NCDESTROY: release the callback before the HWND is reused.
                Dispose();
                break;
        }

        return DefSubclassProc(window, message, wParam, lParam);
    }

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate nint WindowSubclassProcedure(
        nint window, uint message, nuint wParam, nint lParam, nuint subclassId, nuint referenceData);

    [DllImport("comctl32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowSubclass(
        nint window, WindowSubclassProcedure callback, nuint subclassId, nuint referenceData);

    [DllImport("comctl32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RemoveWindowSubclass(
        nint window, WindowSubclassProcedure callback, nuint subclassId);

    [DllImport("comctl32.dll", ExactSpelling = true)]
    private static extern nint DefSubclassProc(nint window, uint message, nuint wParam, nint lParam);

    [DllImport("user32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(
        nint window, nint insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("dwmapi.dll", ExactSpelling = true)]
    private static extern int DwmSetWindowAttribute(
        nint window, uint attribute, ref int value, int valueSize);
}
