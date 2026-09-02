using System.Runtime.InteropServices;
using Sidey.Core.Domain;

namespace Sidey.Platform.Windows;

public static class WindowsTaskbarService
{
    private const int MinimumShownThickness = 8;
    private const int EdgeTolerance = 2;

    public static int VisibleInset(
        NativePixelRect monitorBounds,
        NativePixelRect workAreaBounds,
        OverlayEdge edge) =>
        AdditionalInset(monitorBounds, workAreaBounds, edge, GetVisibleTaskbarBounds());

    public static int AdditionalInset(
        NativePixelRect monitorBounds,
        NativePixelRect workAreaBounds,
        OverlayEdge edge,
        IReadOnlyList<NativePixelRect> taskbarBounds)
    {
        if (!monitorBounds.IsValid || !workAreaBounds.IsValid)
        {
            throw new ArgumentOutOfRangeException(nameof(monitorBounds));
        }

        var inset = 0;
        foreach (var taskbar in taskbarBounds)
        {
            if (!TryIntersect(monitorBounds, taskbar, out var visible))
            {
                continue;
            }

            var candidate = edge switch
            {
                OverlayEdge.Bottom
                    when Touches(visible.Y + visible.Height, monitorBounds.Y + monitorBounds.Height)
                         && IsHorizontal(visible)
                         && visible.Height >= MinimumShownThickness =>
                    workAreaBounds.Y + workAreaBounds.Height - visible.Y,
                OverlayEdge.Top
                    when Touches(visible.Y, monitorBounds.Y)
                         && IsHorizontal(visible)
                         && visible.Height >= MinimumShownThickness =>
                    visible.Y + visible.Height - workAreaBounds.Y,
                OverlayEdge.Left
                    when Touches(visible.X, monitorBounds.X)
                         && IsVertical(visible)
                         && visible.Width >= MinimumShownThickness =>
                    visible.X + visible.Width - workAreaBounds.X,
                OverlayEdge.Right
                    when Touches(visible.X + visible.Width, monitorBounds.X + monitorBounds.Width)
                         && IsVertical(visible)
                         && visible.Width >= MinimumShownThickness =>
                    workAreaBounds.X + workAreaBounds.Width - visible.X,
                _ => 0,
            };
            inset = Math.Max(inset, Math.Max(0, candidate));
        }

        return inset;
    }

    private static IReadOnlyList<NativePixelRect> GetVisibleTaskbarBounds()
    {
        if (!OperatingSystem.IsWindows())
        {
            return [];
        }

        var bounds = new List<NativePixelRect>();
        AddVisibleBounds(NativeMethods.FindWindow("Shell_TrayWnd", null), bounds);

        var previous = nint.Zero;
        while (true)
        {
            var taskbar = NativeMethods.FindWindowEx(
                nint.Zero,
                previous,
                "Shell_SecondaryTrayWnd",
                null);
            if (taskbar == nint.Zero)
            {
                break;
            }

            AddVisibleBounds(taskbar, bounds);
            previous = taskbar;
        }
        return bounds;
    }

    private static void AddVisibleBounds(nint window, ICollection<NativePixelRect> bounds)
    {
        if (window == nint.Zero
            || !NativeMethods.IsWindowVisible(window)
            || !NativeMethods.GetWindowRect(window, out var rectangle))
        {
            return;
        }

        var width = rectangle.Right - rectangle.Left;
        var height = rectangle.Bottom - rectangle.Top;
        if (width > 0 && height > 0)
        {
            bounds.Add(new NativePixelRect(rectangle.Left, rectangle.Top, width, height));
        }
    }

    private static bool TryIntersect(
        NativePixelRect first,
        NativePixelRect second,
        out NativePixelRect intersection)
    {
        var left = Math.Max(first.X, second.X);
        var top = Math.Max(first.Y, second.Y);
        var right = Math.Min(first.X + first.Width, second.X + second.Width);
        var bottom = Math.Min(first.Y + first.Height, second.Y + second.Height);
        intersection = new NativePixelRect(left, top, right - left, bottom - top);
        return intersection.IsValid;
    }

    private static bool Touches(int first, int second) =>
        Math.Abs(first - second) <= EdgeTolerance;

    private static bool IsHorizontal(NativePixelRect bounds) => bounds.Width > bounds.Height;

    private static bool IsVertical(NativePixelRect bounds) => bounds.Height > bounds.Width;

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    private static class NativeMethods
    {
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindowVisible(nint window);

        [DllImport("user32.dll", EntryPoint = "FindWindowW", CharSet = CharSet.Unicode)]
        public static extern nint FindWindow(string className, string? windowName);

        [DllImport("user32.dll", EntryPoint = "FindWindowExW", CharSet = CharSet.Unicode)]
        public static extern nint FindWindowEx(
            nint parent,
            nint childAfter,
            string className,
            string? windowName);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetWindowRect(nint window, out NativeRect rectangle);
    }
}
