using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Sidey.Platform.Windows;

/// <summary>Receives lock and suspend notifications on the existing UI window.</summary>
public sealed class WindowsFeedbackWindowMonitor : IDisposable
{
    private readonly nint _window;
    private readonly Action _stop;
    private readonly Action? _resume;
    private readonly SubclassProc _proc;
    private const nuint SubclassId = 0x51DE09;
    public WindowsFeedbackWindowMonitor(nint window, Action stop, Action? resume = null)
    {
        _window = window;
        _stop = stop;
        _resume = resume;
        _proc = WindowProc;
        if (!SetWindowSubclass(window, _proc, SubclassId, 0))
            throw new Win32Exception();
        if (!WTSRegisterSessionNotification(window, 0))
        {
            RemoveWindowSubclass(window, _proc, SubclassId);
            throw new Win32Exception();
        }
    }
    private nint WindowProc(nint window, uint message, nuint wParam, nint lParam, nuint id, nuint data)
    {
        if ((message == 0x02B1 && wParam is 0x7 or 0x6) || (message == 0x0218 && wParam == 4))
            _stop();
        if (message == 0x0218 && wParam == 0x12) // PBT_APMRESUMEAUTOMATIC, including unattended wake.
            _resume?.Invoke();
        return DefSubclassProc(window, message, wParam, lParam);
    }
    public void Dispose()
    {
        WTSUnRegisterSessionNotification(_window);
        RemoveWindowSubclass(_window, _proc, SubclassId);
    }
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate nint SubclassProc(nint window, uint message, nuint wParam, nint lParam, nuint id, nuint data);
    [DllImport("comctl32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowSubclass(nint window, SubclassProc proc, nuint id, nuint data);
    [DllImport("comctl32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RemoveWindowSubclass(nint window, SubclassProc proc, nuint id);
    [DllImport("comctl32.dll")] private static extern nint DefSubclassProc(nint window, uint message, nuint wParam, nint lParam);
    [DllImport("wtsapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool WTSRegisterSessionNotification(nint window, uint flags);
    [DllImport("wtsapi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool WTSUnRegisterSessionNotification(nint window);
}
