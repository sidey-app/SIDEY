using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Sidey.Platform.Windows;

public sealed class WindowsMinimumSizeController : IDisposable
{
    private const uint GetMinMaxInfoMessage = 0x0024;
    private const nuint SubclassId = 0x53494445;

    private readonly WindowSubclassProcedure _windowProcedure;
    private readonly ResponsiveWindowSize _minimumSize;
    private nint _windowHandle;

    public WindowsMinimumSizeController(
        nint windowHandle,
        ResponsiveWindowSize minimumSize)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("Window sizing requires Windows.");
        }

        if (windowHandle == nint.Zero)
        {
            throw new ArgumentException("A valid window handle is required.", nameof(windowHandle));
        }

        if (minimumSize.Width <= 0 || minimumSize.Height <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(minimumSize),
                "The minimum window size must be positive.");
        }

        _windowHandle = windowHandle;
        _minimumSize = minimumSize;
        _windowProcedure = WindowProcedure;
        if (!SetWindowSubclass(
            _windowHandle,
            _windowProcedure,
            SubclassId,
            nuint.Zero))
        {
            _windowHandle = nint.Zero;
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }

    internal static ResponsiveWindowSize ClampMinimumTrackSize(
        ResponsiveWindowSize current,
        ResponsiveWindowSize minimum) => new(
            Math.Max(current.Width, minimum.Width),
            Math.Max(current.Height, minimum.Height));

    public void Dispose()
    {
        nint windowHandle = _windowHandle;
        if (windowHandle == nint.Zero)
        {
            return;
        }

        _windowHandle = nint.Zero;
        _ = RemoveWindowSubclass(windowHandle, _windowProcedure, SubclassId);
        GC.KeepAlive(_windowProcedure);
    }

    private nint WindowProcedure(
        nint windowHandle,
        uint message,
        nuint wParam,
        nint lParam,
        nuint subclassId,
        nuint referenceData)
    {
        _ = subclassId;
        _ = referenceData;
        if (message == GetMinMaxInfoMessage && lParam != nint.Zero)
        {
            MinMaxInfo info = Marshal.PtrToStructure<MinMaxInfo>(lParam);
            ResponsiveWindowSize constrained = ClampMinimumTrackSize(
                new ResponsiveWindowSize(
                    info.MinimumTrackSize.X,
                    info.MinimumTrackSize.Y),
                _minimumSize);
            info.MinimumTrackSize.X = constrained.Width;
            info.MinimumTrackSize.Y = constrained.Height;
            Marshal.StructureToPtr(info, lParam, fDeleteOld: false);
        }

        return DefSubclassProc(windowHandle, message, wParam, lParam);
    }

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate nint WindowSubclassProcedure(
        nint windowHandle,
        uint message,
        nuint wParam,
        nint lParam,
        nuint subclassId,
        nuint referenceData);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MinMaxInfo
    {
        public NativePoint Reserved;
        public NativePoint MaximumSize;
        public NativePoint MaximumPosition;
        public NativePoint MinimumTrackSize;
        public NativePoint MaximumTrackSize;
    }

    [DllImport("comctl32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowSubclass(
        nint windowHandle,
        WindowSubclassProcedure windowProcedure,
        nuint subclassId,
        nuint referenceData);

    [DllImport("comctl32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RemoveWindowSubclass(
        nint windowHandle,
        WindowSubclassProcedure windowProcedure,
        nuint subclassId);

    [DllImport("comctl32.dll", ExactSpelling = true)]
    private static extern nint DefSubclassProc(
        nint windowHandle,
        uint message,
        nuint wParam,
        nint lParam);
}
