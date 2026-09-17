using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using WinRT.Interop;

namespace Sidey.App.Windowing;

internal static class SideyWindowActivation
{
    internal static void BringToForeground(Window window)
    {
        nint handle = WindowNative.GetWindowHandle(window);
        if (handle == nint.Zero)
        {
            return;
        }

        _ = NativeMethods.ShowWindow(handle, 9);
        _ = NativeMethods.BringWindowToTop(handle);
        _ = NativeMethods.SetForegroundWindow(handle);
    }

    // WS_EX_NOACTIVATE keeps a notice from becoming the foreground window, even when clicked.
    internal static void PreventActivation(nint handle)
    {
        const int ExtendedStyleIndex = -20; // GWL_EXSTYLE
        const nint NoActivate = 0x08000000; // WS_EX_NOACTIVATE
        if (handle == nint.Zero)
        {
            return;
        }

        nint style = NativeMethods.GetWindowLongPtr(handle, ExtendedStyleIndex);
        _ = NativeMethods.SetWindowLongPtr(handle, ExtendedStyleIndex, style | NoActivate);
    }

    private static class NativeMethods
    {
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool ShowWindow(nint window, int command);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool BringWindowToTop(nint window);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetForegroundWindow(nint window);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
        internal static extern nint GetWindowLongPtr(nint window, int index);

        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
        internal static extern nint SetWindowLongPtr(nint window, int index, nint value);
    }
}
