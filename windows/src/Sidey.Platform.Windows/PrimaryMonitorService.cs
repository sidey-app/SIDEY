using System.ComponentModel;
using System.Drawing;
using System.Runtime.InteropServices;
using Windows.Win32;
using Windows.Win32.Graphics.Gdi;

namespace Sidey.Platform.Windows;

public sealed record PrimaryMonitorInfo(
    NativePixelRect WorkAreaPixels,
    uint Dpi);

public static class PrimaryMonitorService
{
    public static PrimaryMonitorInfo GetPrimary()
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("Monitor discovery requires Windows.");
        }

        var monitor = PInvoke.MonitorFromPoint(
            new Point(0, 0),
            MONITOR_FROM_FLAGS.MONITOR_DEFAULTTOPRIMARY);
        var info = new MONITORINFO
        {
            cbSize = (uint)Marshal.SizeOf<MONITORINFO>(),
        };
        if (!PInvoke.GetMonitorInfo(monitor, ref info))
        {
            throw new Win32Exception(Marshal.GetLastPInvokeError(), "GetMonitorInfoW failed.");
        }

        var work = info.rcWork;
        return new PrimaryMonitorInfo(
            new NativePixelRect(
                work.left,
                work.top,
                work.right - work.left,
                work.bottom - work.top),
            PInvoke.GetDpiForSystem());
    }
}
