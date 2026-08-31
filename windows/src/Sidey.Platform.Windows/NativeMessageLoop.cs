using System.ComponentModel;
using System.Runtime.InteropServices;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.UI.WindowsAndMessaging;

namespace Sidey.Platform.Windows;

public static class NativeMessageLoop
{
    public static void Run()
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Win32 message loop requires Windows.");
        }

        while (true)
        {
            var result = PInvoke.GetMessage(out var message, HWND.Null, 0, 0);
            if (result == 0)
            {
                return;
            }

            if (result == -1)
            {
                throw new Win32Exception(Marshal.GetLastPInvokeError(), "GetMessageW failed.");
            }

            PInvoke.TranslateMessage(message);
            PInvoke.DispatchMessage(message);
        }
    }
}
