using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace Sidey.Uninstaller
{
    public static class Program
    {
        private const string CleanupArgument = "--cleanup";
        private const string CleanupCredentialsArgument = "--cleanup-credentials";
        private const string CleanupLocalDataArgument = "--cleanup-local-data";
        private const string LegacyMsiUninstallArgument = "--uninstall-legacy-msi";
        private const string CredentialFilter = "SIDEY/*";
        private const string UpgradeCode = "{E744D02B-C3CF-41CE-A4C9-9BA1EB10C6B9}";
        private const int ErrorNotFound = 1168;
        private const int ErrorProductNotInstalled = 1605;
        private const uint ErrorSuccess = 0;
        private const uint ErrorNoMoreItems = 259;

        [STAThread]
        public static int Main(string[] arguments)
        {
            if (arguments.Length == 1
                && string.Equals(arguments[0], CleanupArgument, StringComparison.OrdinalIgnoreCase))
            {
                int localDataResult = RemoveCurrentUserData();
                int credentialsResult = RemoveCurrentUserCredentials();
                return localDataResult != 0 ? localDataResult : credentialsResult;
            }
            if (arguments.Length == 1
                && string.Equals(
                    arguments[0],
                    CleanupLocalDataArgument,
                    StringComparison.OrdinalIgnoreCase))
            {
                return RemoveCurrentUserData();
            }
            if (arguments.Length == 1
                && string.Equals(
                    arguments[0],
                    CleanupCredentialsArgument,
                    StringComparison.OrdinalIgnoreCase))
            {
                return RemoveCurrentUserCredentials();
            }
            if (arguments.Length == 1
                && string.Equals(
                    arguments[0],
                    LegacyMsiUninstallArgument,
                    StringComparison.OrdinalIgnoreCase))
            {
                return UninstallLegacyMsi();
            }

            if (arguments.Length != 0)
            {
                return 64;
            }

            try
            {
                string productCode = FindInstalledProductCode();
                if (string.IsNullOrEmpty(productCode))
                {
                    ShowMessage(
                        "SIDEY is not installed.",
                        "SIDEY가 설치되어 있지 않습니다.",
                        0x30);
                    return 2;
                }

                string systemDirectory = Environment.GetFolderPath(Environment.SpecialFolder.System);
                string installerPath = Path.Combine(systemDirectory, "msiexec.exe");
                ProcessStartInfo start = new ProcessStartInfo();
                start.FileName = installerPath;
                start.Arguments = "/x " + QuoteArgument(productCode);
                start.UseShellExecute = true;
                start.Verb = "runas";
                Process.Start(start);

                // Do not wait here. The installed helper must exit before MSI
                // removes it and the rest of the legacy installation folder.
                return 0;
            }
            catch (Exception exception)
            {
                ShowMessage(
                    "SIDEY could not start Windows Installer.\r\n\r\n" + exception.Message,
                    "Windows Installer를 시작하지 못했습니다.\r\n\r\n" + exception.Message,
                    0x10);
                return 1;
            }
        }

        private static int UninstallLegacyMsi()
        {
            try
            {
                string productCode = FindInstalledProductCode();
                if (string.IsNullOrEmpty(productCode))
                {
                    return 0;
                }

                string systemDirectory = Environment.GetFolderPath(Environment.SpecialFolder.System);
                ProcessStartInfo start = new ProcessStartInfo();
                start.FileName = Path.Combine(systemDirectory, "msiexec.exe");
                start.Arguments = "/x " + QuoteArgument(productCode) + " /quiet /norestart";
                start.UseShellExecute = false;
                using (Process process = Process.Start(start))
                {
                    if (process == null)
                    {
                        return 1;
                    }

                    process.WaitForExit();
                    return process.ExitCode == ErrorProductNotInstalled
                        ? 0
                        : process.ExitCode;
                }
            }
            catch
            {
                return 1;
            }
        }

        private static string FindInstalledProductCode()
        {
            StringBuilder productCode = new StringBuilder(39);
            uint result = MsiEnumRelatedProducts(UpgradeCode, 0, 0, productCode);
            if (result == ErrorNoMoreItems)
            {
                return null;
            }
            if (result != ErrorSuccess)
            {
                throw new System.ComponentModel.Win32Exception(
                    unchecked((int)result),
                    "Windows Installer product lookup failed.");
            }

            return productCode.ToString();
        }

        private static int RemoveCurrentUserData()
        {
            try
            {
                string localAppData = Environment.GetFolderPath(
                    Environment.SpecialFolder.LocalApplicationData);
                if (string.IsNullOrWhiteSpace(localAppData))
                {
                    throw new InvalidOperationException("Local application data is unavailable.");
                }

                string normalizedLocalAppData = Path.GetFullPath(localAppData)
                    .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                string dataRoot = Path.GetFullPath(Path.Combine(normalizedLocalAppData, "SIDEY"));
                DirectoryInfo parent = Directory.GetParent(dataRoot);
                if (parent == null
                    || !string.Equals(
                        parent.FullName.TrimEnd(
                            Path.DirectorySeparatorChar,
                            Path.AltDirectorySeparatorChar),
                        normalizedLocalAppData,
                        StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException("Unsafe SIDEY data directory.");
                }

                if (Directory.Exists(dataRoot))
                {
                    Directory.Delete(dataRoot, true);
                }

                return 0;
            }
            catch
            {
                return 3;
            }
        }

        private static int RemoveCurrentUserCredentials()
        {
            try
            {
                DeleteSideyCredentials();
                return 0;
            }
            catch
            {
                return 3;
            }
        }

        private static void DeleteSideyCredentials()
        {
            int count;
            IntPtr credentials;
            if (!CredEnumerate(CredentialFilter, 0, out count, out credentials))
            {
                int error = Marshal.GetLastWin32Error();
                if (error == ErrorNotFound)
                {
                    return;
                }

                throw new System.ComponentModel.Win32Exception(
                    error,
                    "Credential Manager enumeration failed.");
            }

            try
            {
                for (int index = 0; index < count; index++)
                {
                    IntPtr pointer = Marshal.ReadIntPtr(credentials, index * IntPtr.Size);
                    NativeCredential credential = (NativeCredential)Marshal.PtrToStructure(
                        pointer,
                        typeof(NativeCredential));
                    if (credential.Type != CredentialType.Generic
                        || string.IsNullOrEmpty(credential.TargetName))
                    {
                        continue;
                    }

                    if (!CredDelete(credential.TargetName, CredentialType.Generic, 0))
                    {
                        int error = Marshal.GetLastWin32Error();
                        if (error != ErrorNotFound)
                        {
                            throw new System.ComponentModel.Win32Exception(
                                error,
                                "Credential Manager delete failed.");
                        }
                    }
                }
            }
            finally
            {
                CredFree(credentials);
            }
        }

        private static string QuoteArgument(string argument)
        {
            return "\"" + argument.Replace("\"", "\\\"") + "\"";
        }

        private static void ShowMessage(string english, string korean, uint type)
        {
            bool useEnglish = System.Globalization.CultureInfo.CurrentUICulture
                .TwoLetterISOLanguageName == "en";
            MessageBox(
                IntPtr.Zero,
                useEnglish ? english : korean,
                useEnglish ? "Uninstall SIDEY" : "SIDEY 제거",
                type);
        }

        private enum CredentialType : uint
        {
            Generic = 1,
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct NativeCredential
        {
            public uint Flags;
            public CredentialType Type;
            public string TargetName;
            public string Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public uint CredentialBlobSize;
            public IntPtr CredentialBlob;
            public uint Persist;
            public uint AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }

        [DllImport("msi.dll", CharSet = CharSet.Unicode)]
        private static extern uint MsiEnumRelatedProducts(
            string upgradeCode,
            uint reserved,
            uint productIndex,
            StringBuilder productCode);

        [DllImport("advapi32.dll", EntryPoint = "CredEnumerateW", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CredEnumerate(
            string filter,
            uint flags,
            out int count,
            out IntPtr credentials);

        [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CredDelete(string target, CredentialType type, uint flags);

        [DllImport("advapi32.dll")]
        private static extern void CredFree(IntPtr buffer);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int MessageBox(
            IntPtr window,
            string text,
            string caption,
            uint type);
    }
}
