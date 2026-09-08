using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

namespace Sidey.Installer
{
    internal static class LanguageSelector
    {
        private delegate IntPtr DialogProc(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll")] private static extern ushort GetUserDefaultUILanguage();
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string name);
        [DllImport("user32.dll")] private static extern bool AllowSetForegroundWindow(uint processId);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr DialogBoxIndirectParam(IntPtr instance, IntPtr template, IntPtr parent, DialogProc callback, IntPtr parameter);
        [DllImport("user32.dll")] private static extern bool EndDialog(IntPtr window, IntPtr result);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool SetWindowText(IntPtr window, string text);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool SetDlgItemText(IntPtr window, int item, string text);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr SendDlgItemMessage(IntPtr window, int item, uint message, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendDlgItemMessageW")]
        private static extern IntPtr InsertLanguage(IntPtr window, int item, uint message, IntPtr index, string text);

        [STAThread]
        private static int Main(string[] arguments)
        {
            try
            {
                int savedLanguage = 0;
                if (arguments.Length > 0) { int.TryParse(arguments[0], out savedLanguage); }
                int systemLanguage = GetUserDefaultUILanguage();
                int selectedLanguage = InstallerLanguages.DefaultSelection(systemLanguage, savedLanguage);
                if (Array.IndexOf(arguments, "--silent") >= 0) { return selectedLanguage; }
                uint installerProcess = 0;
                if (arguments.Length > 1) { uint.TryParse(arguments[1], out installerProcess); }
                InstallerLanguage[] languages = InstallerLanguages.Ordered(systemLanguage);

                using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("Sidey.Installer.LanguageDialog"))
                using (var reader = new BinaryReader(stream))
                using (var icon = Icon.ExtractAssociatedIcon(Process.GetCurrentProcess().MainModule.FileName))
                {
                    byte[] bytes = reader.ReadBytes(checked((int)stream.Length));
                    IntPtr template = Marshal.AllocHGlobal(bytes.Length);
                    try
                    {
                        Marshal.Copy(bytes, 0, template, bytes.Length);
                        DialogProc callback = delegate(IntPtr window, uint message, IntPtr wParam, IntPtr lParam) {
                            if (message == 0x110) // WM_INITDIALOG
                            {
                                SetWindowText(window, "Installer Language");
                                SetDlgItemText(window, 1007, "Please select a language.");
                                SendDlgItemMessage(window, 1008, 0x170, icon.Handle, IntPtr.Zero); // STM_SETICON
                                for (int index = 0; index < languages.Length; index++)
                                {
                                    // CB_INSERTSTRING preserves our order even though the
                                    // original NSIS template has the CBS_SORT style.
                                    InsertLanguage(window, 1002, 0x14a, (IntPtr)index, languages[index].DisplayName);
                                    if (languages[index].Id == selectedLanguage)
                                    {
                                        SendDlgItemMessage(window, 1002, 0x14e, (IntPtr)index, IntPtr.Zero); // CB_SETCURSEL
                                    }
                                }
                                return (IntPtr)1;
                            }
                            if (message == 0x111) // WM_COMMAND
                            {
                                int command = (int)(wParam.ToInt64() & 0xffff);
                                if (command == 1) // IDOK
                                {
                                    int index = SendDlgItemMessage(window, 1002, 0x147, IntPtr.Zero, IntPtr.Zero).ToInt32();
                                    // Transfer activation before the selector loses foreground.
                                    if (installerProcess != 0) { AllowSetForegroundWindow(installerProcess); }
                                    EndDialog(window, (IntPtr)(index >= 0 && index < languages.Length ? languages[index].Id : 1));
                                    return (IntPtr)1;
                                }
                                if (command == 2) // IDCANCEL (also Escape / window close)
                                {
                                    EndDialog(window, IntPtr.Zero);
                                    return (IntPtr)1;
                                }
                            }
                            return IntPtr.Zero;
                        };
                        int result = DialogBoxIndirectParam(GetModuleHandle(null), template, IntPtr.Zero, callback, IntPtr.Zero).ToInt32();
                        GC.KeepAlive(callback);
                        return result == -1 ? 1 : result;
                    }
                    finally { Marshal.FreeHGlobal(template); }
                }
            }
            catch { return 1; }
        }
    }
}
