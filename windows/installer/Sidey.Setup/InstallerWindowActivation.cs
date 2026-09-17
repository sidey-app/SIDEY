using System;
using System.Runtime.InteropServices;
using System.Threading;

namespace Sidey.Installer
{
    internal interface IInstallerWindowActivationApi
    {
        public IntPtr FindMarkedWindow();

        public IntPtr GetLastActivePopup(IntPtr window);

        public bool IsWindow(IntPtr window);

        public bool IsMinimized(IntPtr window);

        public void ShowWindow(IntPtr window, int command);

        public bool SetForegroundWindow(IntPtr window);

        public void FlashWindow(IntPtr window);

        public void Delay(int milliseconds);
    }

    internal static class InstallerWindowActivation
    {
        internal const string WindowPropertyName = "SIDEY.Setup.Activation.1";
        internal const int ShowNormal = 5;
        internal const int Restore = 9;
        private const int SearchAttempts = 100;
        private const int SearchDelayMilliseconds = 50;
        private const uint FlashTaskbar = 2;

        internal static bool TryActivateExisting()
        {
            return TryActivateExisting(
                new NativeInstallerWindowActivationApi(),
                SearchAttempts,
                SearchDelayMilliseconds);
        }

        internal static bool TryActivateExisting(
            IInstallerWindowActivationApi api,
            int searchAttempts,
            int searchDelayMilliseconds)
        {
            if (api == null)
            {
                throw new ArgumentNullException(nameof(api));
            }

            if (searchAttempts <= 0)
            {
                throw new ArgumentOutOfRangeException(nameof(searchAttempts));
            }

            for (int attempt = 0; attempt < searchAttempts; attempt++)
            {
                IntPtr rootWindow = api.FindMarkedWindow();
                if (rootWindow != IntPtr.Zero && api.IsWindow(rootWindow))
                {
                    api.ShowWindow(
                        rootWindow,
                        api.IsMinimized(rootWindow) ? Restore : ShowNormal);

                    IntPtr window = api.GetLastActivePopup(rootWindow);
                    if (window == IntPtr.Zero || !api.IsWindow(window))
                    {
                        window = rootWindow;
                    }
                    else if (window != rootWindow)
                    {
                        api.ShowWindow(window, api.IsMinimized(window) ? Restore : ShowNormal);
                    }

                    if (!api.SetForegroundWindow(window))
                    {
                        api.FlashWindow(window);
                    }

                    return true;
                }

                if (attempt + 1 < searchAttempts)
                {
                    api.Delay(searchDelayMilliseconds);
                }
            }

            return false;
        }

        internal static void MarkWindow(IntPtr window)
        {
            if (window != IntPtr.Zero)
            {
                NativeMethods.SetProp(window, WindowPropertyName, new IntPtr(1));
            }
        }

        internal static void UnmarkWindow(IntPtr window)
        {
            if (window != IntPtr.Zero)
            {
                NativeMethods.RemoveProp(window, WindowPropertyName);
            }
        }

        private sealed class NativeInstallerWindowActivationApi : IInstallerWindowActivationApi
        {
            public IntPtr FindMarkedWindow()
            {
                IntPtr foundWindow = IntPtr.Zero;
                NativeMethods.EnumWindows(delegate (IntPtr window, IntPtr state)
                {
                    if (NativeMethods.IsWindowVisible(window)
                        && NativeMethods.GetProp(window, WindowPropertyName) != IntPtr.Zero)
                    {
                        foundWindow = window;
                        return false;
                    }

                    return true;
                }, IntPtr.Zero);
                return foundWindow;
            }

            public bool IsMinimized(IntPtr window)
            {
                return NativeMethods.IsIconic(window);
            }

            public bool IsWindow(IntPtr window)
            {
                return NativeMethods.IsWindow(window);
            }

            public IntPtr GetLastActivePopup(IntPtr window)
            {
                return NativeMethods.GetLastActivePopup(window);
            }

            public void ShowWindow(IntPtr window, int command)
            {
                NativeMethods.ShowWindowAsync(window, command);
            }

            public bool SetForegroundWindow(IntPtr window)
            {
                return NativeMethods.SetForegroundWindow(window);
            }

            public void FlashWindow(IntPtr window)
            {
                var information = new NativeMethods.FlashWindowInformation
                {
                    _size = (uint)Marshal.SizeOf(typeof(NativeMethods.FlashWindowInformation)),
                    _window = window,
                    _flags = FlashTaskbar,
                    _count = 3,
                    _timeout = 0,
                };
                NativeMethods.FlashWindowEx(ref information);
            }

            public void Delay(int milliseconds)
            {
                Thread.Sleep(milliseconds);
            }
        }

        private static class NativeMethods
        {
            internal delegate bool EnumWindowsProcedure(IntPtr window, IntPtr state);

            [StructLayout(LayoutKind.Sequential)]
            internal struct FlashWindowInformation
            {
                internal uint _size;
                internal IntPtr _window;
                internal uint _flags;
                internal uint _count;
                internal uint _timeout;
            }

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool EnumWindows(EnumWindowsProcedure callback, IntPtr state);

            [DllImport("user32.dll", CharSet = CharSet.Unicode)]
            internal static extern IntPtr GetProp(IntPtr window, string name);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool IsIconic(IntPtr window);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool IsWindow(IntPtr window);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool IsWindowVisible(IntPtr window);

            [DllImport("user32.dll")]
            internal static extern IntPtr GetLastActivePopup(IntPtr window);

            [DllImport("user32.dll", CharSet = CharSet.Unicode)]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool SetProp(IntPtr window, string name, IntPtr data);

            [DllImport("user32.dll", CharSet = CharSet.Unicode)]
            internal static extern IntPtr RemoveProp(IntPtr window, string name);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool ShowWindowAsync(IntPtr window, int command);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool SetForegroundWindow(IntPtr window);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool FlashWindowEx(ref FlashWindowInformation information);
        }
    }
}
