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
        bool activated = NativeMethods.SetForegroundWindow(handle);
        StartupDiagnostics.Stage($"window-foreground result={(activated ? "success" : "denied")}");
        if (!activated)
        {
            // Windows can decline activation when the user has moved to another app.
            // Notify through the taskbar without changing global foreground policy.
            var flash = new NativeMethods.FlashWindowInfo
            {
                Size = (uint)Marshal.SizeOf<NativeMethods.FlashWindowInfo>(),
                Window = handle,
                Flags = 0x00000002 | 0x0000000C, // FLASHW_TRAY | FLASHW_TIMERNOFG
                Count = 3,
            };
            _ = NativeMethods.FlashWindowEx(ref flash);
        }
    }

    private static class NativeMethods
    {
        [StructLayout(LayoutKind.Sequential)]
        internal struct FlashWindowInfo
        {
            public uint Size;
            public nint Window;
            public uint Flags;
            public uint Count;
            public uint Timeout;
        }

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool FlashWindowEx(ref FlashWindowInfo info);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool ShowWindow(nint window, int command);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool BringWindowToTop(nint window);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetForegroundWindow(nint window);
    }
}
