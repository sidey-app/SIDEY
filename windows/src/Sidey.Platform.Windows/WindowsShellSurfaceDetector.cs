using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace Sidey.Platform.Windows;

public static class WindowsShellSurfaceDetector
{
    private static readonly object CacheGate = new();
    private static nint _cachedWindow;
    private static bool _cachedShouldYield;

    public static nint ForegroundSurface()
    {
        if (!OperatingSystem.IsWindows())
        {
            return nint.Zero;
        }

        nint transientPopup = VisibleTransientPopup();
        if (transientPopup != nint.Zero)
        {
            return transientPopup;
        }

        nint foreground = NativeMethods.GetForegroundWindow();
        if (foreground == nint.Zero)
        {
            return nint.Zero;
        }

        nint root = NativeMethods.GetAncestor(foreground, 2);
        if (root != nint.Zero)
        {
            foreground = root;
        }

        lock (CacheGate)
        {
            if (foreground == _cachedWindow)
            {
                return _cachedShouldYield ? foreground : nint.Zero;
            }

            _cachedWindow = foreground;
            _cachedShouldYield = IsShellSurface(foreground);
            return _cachedShouldYield ? foreground : nint.Zero;
        }
    }

    private static nint VisibleTransientPopup()
    {
        nint popup = nint.Zero;
        _ = NativeMethods.EnumWindows((window, _) =>
        {
            if (!NativeMethods.IsWindowVisible(window))
            {
                return true;
            }

            var className = new StringBuilder(256);
            _ = NativeMethods.GetClassName(window, className, className.Capacity);
            nint style = NativeMethods.GetWindowLongPtr(window, -16);
            nint extendedStyle = NativeMethods.GetWindowLongPtr(window, -20);
            if (!WindowsShellSurfacePolicy.IsTransientPopup(
                    className.ToString(),
                    style,
                    extendedStyle))
            {
                return true;
            }

            popup = window;
            return false;
        }, nint.Zero);
        return popup;
    }

    private static bool IsShellSurface(nint window)
    {
        _ = NativeMethods.GetWindowThreadProcessId(window, out uint processId);
        if (processId == 0)
        {
            return false;
        }

        try
        {
            using Process process = Process.GetProcessById((int)processId);
            var className = new StringBuilder(256);
            _ = NativeMethods.GetClassName(window, className, className.Capacity);
            return WindowsShellSurfacePolicy.ShouldYield(process.ProcessName, className.ToString());
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return false;
        }
    }

    private static class NativeMethods
    {
        [DllImport("user32.dll")]
        internal static extern nint GetForegroundWindow();

        [DllImport("user32.dll")]
        internal static extern nint GetAncestor(nint window, uint flags);

        [DllImport("user32.dll")]
        internal static extern uint GetWindowThreadProcessId(nint window, out uint processId);

        [DllImport("user32.dll", EntryPoint = "GetClassNameW", CharSet = CharSet.Unicode)]
        internal static extern int GetClassName(nint window, StringBuilder className, int maximumCount);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool EnumWindows(EnumWindowsCallback callback, nint parameter);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsWindowVisible(nint window);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
        internal static extern nint GetWindowLongPtr(nint window, int index);

        internal delegate bool EnumWindowsCallback(nint window, nint parameter);
    }
}

public static class WindowsShellSurfacePolicy
{
    private static readonly HashSet<string> ShellProcesses = new(StringComparer.OrdinalIgnoreCase)
    {
        "SearchApp",
        "SearchHost",
        "SearchUI",
        "ShellExperienceHost",
        "ShellHost",
        "StartMenuExperienceHost",
        "TextInputHost",
        "MicrosoftStartFeedProvider",
        "WidgetBoard",
        "Widgets",
        "WidgetsBoard",
        "WidgetService",
    };

    public static bool ShouldYield(string? processName, string? windowClass)
    {
        if (string.IsNullOrWhiteSpace(processName))
        {
            return false;
        }

        if (ShellProcesses.Contains(processName))
        {
            return true;
        }

        return StringComparer.OrdinalIgnoreCase.Equals(processName, "explorer")
            && IsExplorerTaskbarSurface(windowClass);
    }

    public static bool IsTransientPopup(
        string? windowClass,
        nint style = default,
        nint extendedStyle = default)
    {
        if (string.IsNullOrWhiteSpace(windowClass))
        {
            return false;
        }

        if (IsPersistentShellWindow(windowClass)
            || StringComparer.OrdinalIgnoreCase.Equals(windowClass, "SIDEY.NativeOverlayWindow"))
        {
            return false;
        }

        bool recognizedClass = StringComparer.OrdinalIgnoreCase.Equals(windowClass, "#32768")
            || StringComparer.OrdinalIgnoreCase.Equals(windowClass, "Xaml_WindowedPopupClass")
            || StringComparer.OrdinalIgnoreCase.Equals(windowClass, "tooltips_class32")
            || windowClass.Contains("PopupWindowSiteBridge", StringComparison.OrdinalIgnoreCase);
        const long popupStyle = 0x80000000L;
        const long toolWindowStyle = 0x00000080L;
        bool transientWindowStyles = (style.ToInt64() & popupStyle) != 0
            && (extendedStyle.ToInt64() & toolWindowStyle) != 0;
        return recognizedClass || transientWindowStyles;
    }

    private static bool IsPersistentShellWindow(string windowClass) =>
        StringComparer.OrdinalIgnoreCase.Equals(windowClass, "Progman")
        || StringComparer.OrdinalIgnoreCase.Equals(windowClass, "WorkerW")
        || StringComparer.OrdinalIgnoreCase.Equals(windowClass, "Shell_TrayWnd")
        || StringComparer.OrdinalIgnoreCase.Equals(windowClass, "Shell_SecondaryTrayWnd");

    private static bool IsExplorerTaskbarSurface(string? windowClass)
    {
        if (string.IsNullOrWhiteSpace(windowClass))
        {
            return false;
        }

        return windowClass.Contains("ControlCenter", StringComparison.OrdinalIgnoreCase)
            || windowClass.Contains("MultitaskingView", StringComparison.OrdinalIgnoreCase)
            || windowClass.Contains("NotifyIconOverflow", StringComparison.OrdinalIgnoreCase)
            || windowClass.Contains("OverflowXamlIsland", StringComparison.OrdinalIgnoreCase)
            || windowClass.Contains("XamlExplorerHostIsland", StringComparison.OrdinalIgnoreCase)
            || StringComparer.OrdinalIgnoreCase.Equals(windowClass, "Shell_TrayWnd")
            || StringComparer.OrdinalIgnoreCase.Equals(windowClass, "Shell_SecondaryTrayWnd");
    }
}
