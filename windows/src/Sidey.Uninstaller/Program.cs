using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32;

namespace Sidey.Uninstaller
{
    public static class Program
    {
        private const string CleanupArgument = "--cleanup";
        private const string CleanupCredentialsArgument = "--cleanup-credentials";
        private const string CleanupLocalDataArgument = "--cleanup-local-data";
        private const string CleanupStartupArgument = "--cleanup-startup";
        private const string CleanupCredentialsAsDesktopUserArgument =
            "--cleanup-credentials-as-desktop-user";
        private const string CleanupLocalDataAsDesktopUserArgument =
            "--cleanup-local-data-as-desktop-user";
        private const string CleanupStartupAsDesktopUserArgument =
            "--cleanup-startup-as-desktop-user";
        private const string LaunchSideyAsDesktopUserArgument =
            "--launch-sidey-as-desktop-user";
        private const string LegacyMsiDetectArgument = "--detect-legacy-msi";
        private const string CredentialFilter = "SIDEY/*";
        private const string StartupRegistryPath =
            @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string StartupValueName = "SIDEY";
        private const string UpgradeCode = "{E744D02B-C3CF-41CE-A4C9-9BA1EB10C6B9}";
        private const int ErrorNotFound = 1168;
        private const int ErrorProductNotInstalled = 1605;
        private const uint ErrorSuccess = 0;
        private const uint ErrorNoMoreItems = 259;

        [STAThread]
        public static int Main(string[] arguments)
        {
            if (arguments.Length == 1
                && string.Equals(
                    arguments[0],
                    LaunchSideyAsDesktopUserArgument,
                    StringComparison.OrdinalIgnoreCase))
            {
                return LaunchSideyAsDesktopUser();
            }
            if (arguments.Length == 1
                && string.Equals(
                    arguments[0],
                    CleanupLocalDataAsDesktopUserArgument,
                    StringComparison.OrdinalIgnoreCase))
            {
                return RunThisHelperAsDesktopUser(CleanupLocalDataArgument);
            }
            if (arguments.Length == 1
                && string.Equals(
                    arguments[0],
                    CleanupCredentialsAsDesktopUserArgument,
                    StringComparison.OrdinalIgnoreCase))
            {
                return RunThisHelperAsDesktopUser(CleanupCredentialsArgument);
            }
            if (arguments.Length == 1
                && string.Equals(
                    arguments[0],
                    CleanupStartupAsDesktopUserArgument,
                    StringComparison.OrdinalIgnoreCase))
            {
                return RunThisHelperAsDesktopUser(CleanupStartupArgument);
            }
            if (arguments.Length == 1
                && string.Equals(arguments[0], CleanupArgument, StringComparison.OrdinalIgnoreCase))
            {
                if (!DesktopUserProcess.IsCurrentDesktopUser())
                {
                    return 5;
                }
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
                if (!DesktopUserProcess.IsCurrentDesktopUser())
                {
                    return 5;
                }
                return RemoveCurrentUserData();
            }
            if (arguments.Length == 1
                && string.Equals(
                    arguments[0],
                    CleanupCredentialsArgument,
                    StringComparison.OrdinalIgnoreCase))
            {
                if (!DesktopUserProcess.IsCurrentDesktopUser())
                {
                    return 5;
                }
                return RemoveCurrentUserCredentials();
            }
            if (arguments.Length == 1
                && string.Equals(
                    arguments[0],
                    CleanupStartupArgument,
                    StringComparison.OrdinalIgnoreCase))
            {
                if (!DesktopUserProcess.IsCurrentDesktopUser())
                {
                    return 5;
                }
                return RemoveCurrentUserStartupRegistration();
            }
            if (arguments.Length == 1
                && string.Equals(
                    arguments[0],
                    LegacyMsiDetectArgument,
                    StringComparison.OrdinalIgnoreCase))
            {
                return DetectLegacyMsi();
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
                var start = new ProcessStartInfo
                {
                    FileName = installerPath,
                    Arguments = "/x " + QuoteArgument(productCode),
                    UseShellExecute = true,
                    Verb = "runas",
                };
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

        private static int LaunchSideyAsDesktopUser()
        {
            try
            {
                string helperPath = Process.GetCurrentProcess().MainModule.FileName;
                DirectoryInfo runtimeDirectory = Directory.GetParent(helperPath);
                DirectoryInfo installDirectory = runtimeDirectory == null
                    ? null
                    : runtimeDirectory.Parent;
                if (installDirectory == null)
                {
                    return 2;
                }

                string launcherPath = Path.Combine(installDirectory.FullName, "SIDEY.exe");
                if (!File.Exists(launcherPath))
                {
                    return 2;
                }

                return DesktopUserProcess.Start(
                    launcherPath,
                    string.Empty,
                    installDirectory.FullName,
                    waitForExit: false);
            }
            catch
            {
                return 5;
            }
        }

        private static int RunThisHelperAsDesktopUser(string argument)
        {
            try
            {
                string helperPath = Process.GetCurrentProcess().MainModule.FileName;
                return DesktopUserProcess.Start(
                    helperPath,
                    QuoteArgument(argument),
                    Path.GetDirectoryName(helperPath),
                    waitForExit: true);
            }
            catch
            {
                return 5;
            }
        }

        private static int DetectLegacyMsi()
        {
            try
            {
                return string.IsNullOrEmpty(FindInstalledProductCode())
                    ? ErrorProductNotInstalled
                    : 0;
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

        private static int RemoveCurrentUserStartupRegistration()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(
                    StartupRegistryPath,
                    writable: true))
                {
                    if (key != null)
                    {
                        key.DeleteValue(StartupValueName, throwOnMissingValue: false);
                    }
                }
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

        private static class DesktopUserProcess
        {
            private const uint CreateUnicodeEnvironment = 0x00000400;
            private const uint Infinite = 0xFFFFFFFF;
            private const uint LogonWithProfile = 0x00000001;
            private const uint ProcessQueryLimitedInformation = 0x1000;
            private const uint SePrivilegeEnabled = 0x00000002;
            private const uint TokenAdjustDefault = 0x0080;
            private const uint TokenAdjustPrivileges = 0x0020;
            private const uint TokenAdjustSessionId = 0x0100;
            private const uint TokenAssignPrimary = 0x0001;
            private const uint TokenDuplicate = 0x0002;
            private const uint TokenQuery = 0x0008;
            private const int SecurityImpersonation = 2;
            private const int TokenElevation = 20;
            private const int TokenPrimary = 1;

            public static int Start(
                string executable,
                string arguments,
                string workingDirectory,
                bool waitForExit)
            {
                bool elevated;
                if (!TryIsCurrentProcessElevated(out elevated))
                {
                    return 5;
                }
                if (!elevated)
                {
                    return IsCurrentDesktopUser()
                        ? StartNormally(executable, arguments, workingDirectory, waitForExit)
                        : 5;
                }

                IntPtr shellWindow = GetShellWindow();
                uint shellProcessId;
                if (shellWindow == IntPtr.Zero
                    || GetWindowThreadProcessId(shellWindow, out shellProcessId) == 0
                    || shellProcessId == 0)
                {
                    return 5;
                }

                IntPtr shellProcess = IntPtr.Zero;
                IntPtr shellToken = IntPtr.Zero;
                IntPtr primaryToken = IntPtr.Zero;
                IntPtr environment = IntPtr.Zero;
                IntPtr currentToken = IntPtr.Zero;
                TokenPrivileges previousPrivileges = new TokenPrivileges();
                bool privilegeChanged = false;
                ProcessInformation processInformation = new ProcessInformation();
                try
                {
                    shellProcess = OpenProcess(
                        ProcessQueryLimitedInformation,
                        false,
                        shellProcessId);
                    if (shellProcess == IntPtr.Zero
                        || !OpenProcessToken(
                            shellProcess,
                            TokenQuery | TokenDuplicate,
                            out shellToken))
                    {
                        return 5;
                    }

                    privilegeChanged = EnableImpersonatePrivilege(
                        out currentToken,
                        out previousPrivileges);
                    if (!privilegeChanged)
                    {
                        return 5;
                    }

                    if (!DuplicateTokenEx(
                        shellToken,
                        TokenQuery | TokenAssignPrimary | TokenDuplicate
                            | TokenAdjustDefault | TokenAdjustSessionId,
                        IntPtr.Zero,
                        SecurityImpersonation,
                        TokenPrimary,
                        out primaryToken))
                    {
                        return 5;
                    }
                    if (!CreateEnvironmentBlock(out environment, primaryToken, false))
                    {
                        return 5;
                    }

                    var commandLine = new StringBuilder(QuoteArgument(executable));
                    if (!string.IsNullOrWhiteSpace(arguments))
                    {
                        commandLine.Append(' ').Append(arguments);
                    }
                    var startupInformation = new StartupInformation
                    {
                        Size = Marshal.SizeOf(typeof(StartupInformation)),
                    };
                    if (!CreateProcessWithTokenW(
                        primaryToken,
                        LogonWithProfile,
                        executable,
                        commandLine,
                        CreateUnicodeEnvironment,
                        environment,
                        workingDirectory,
                        ref startupInformation,
                        out processInformation))
                    {
                        return 5;
                    }

                    if (!waitForExit)
                    {
                        return 0;
                    }
                    if (WaitForSingleObject(processInformation.Process, Infinite) == 0xFFFFFFFF)
                    {
                        return 5;
                    }
                    int exitCode;
                    return GetExitCodeProcess(processInformation.Process, out exitCode)
                        ? exitCode
                        : 5;
                }
                finally
                {
                    if (processInformation.Thread != IntPtr.Zero)
                        CloseHandle(processInformation.Thread);
                    if (processInformation.Process != IntPtr.Zero)
                        CloseHandle(processInformation.Process);
                    if (environment != IntPtr.Zero)
                        DestroyEnvironmentBlock(environment);
                    if (primaryToken != IntPtr.Zero)
                        CloseHandle(primaryToken);
                    if (shellToken != IntPtr.Zero)
                        CloseHandle(shellToken);
                    if (shellProcess != IntPtr.Zero)
                        CloseHandle(shellProcess);
                    if (privilegeChanged && currentToken != IntPtr.Zero)
                    {
                        TokenPrivileges ignored;
                        uint ignoredLength;
                        AdjustTokenPrivileges(
                            currentToken,
                            false,
                            ref previousPrivileges,
                            Marshal.SizeOf(typeof(TokenPrivileges)),
                            out ignored,
                            out ignoredLength);
                    }
                    if (currentToken != IntPtr.Zero)
                        CloseHandle(currentToken);
                }
            }

            private static int StartNormally(
                string executable,
                string arguments,
                string workingDirectory,
                bool waitForExit)
            {
                var start = new ProcessStartInfo
                {
                    FileName = executable,
                    Arguments = arguments,
                    WorkingDirectory = workingDirectory,
                    UseShellExecute = false,
                };
                using (Process process = Process.Start(start))
                {
                    if (process == null)
                    {
                        return 5;
                    }
                    if (!waitForExit)
                    {
                        return 0;
                    }
                    process.WaitForExit();
                    return process.ExitCode;
                }
            }

            public static bool IsCurrentDesktopUser()
            {
                IntPtr shellWindow = GetShellWindow();
                uint shellProcessId;
                if (shellWindow == IntPtr.Zero
                    || GetWindowThreadProcessId(shellWindow, out shellProcessId) == 0
                    || shellProcessId == 0)
                {
                    return false;
                }

                IntPtr shellProcess = IntPtr.Zero;
                IntPtr shellToken = IntPtr.Zero;
                try
                {
                    shellProcess = OpenProcess(
                        ProcessQueryLimitedInformation,
                        false,
                        shellProcessId);
                    if (shellProcess == IntPtr.Zero
                        || !OpenProcessToken(shellProcess, TokenQuery, out shellToken))
                    {
                        return false;
                    }

                    using (WindowsIdentity currentIdentity = WindowsIdentity.GetCurrent())
                    using (var shellIdentity = new WindowsIdentity(shellToken))
                    {
                        return currentIdentity.User != null
                            && shellIdentity.User != null
                            && currentIdentity.User.Equals(shellIdentity.User);
                    }
                }
                catch
                {
                    return false;
                }
                finally
                {
                    if (shellToken != IntPtr.Zero)
                        CloseHandle(shellToken);
                    if (shellProcess != IntPtr.Zero)
                        CloseHandle(shellProcess);
                }
            }

            private static bool TryIsCurrentProcessElevated(out bool elevated)
            {
                elevated = false;
                IntPtr token;
                if (!OpenProcessToken(GetCurrentProcess(), TokenQuery, out token))
                {
                    return false;
                }
                try
                {
                    int elevation;
                    uint returnedLength;
                    if (!GetTokenInformation(
                        token,
                        TokenElevation,
                        out elevation,
                        sizeof(int),
                        out returnedLength))
                    {
                        return false;
                    }
                    elevated = elevation != 0;
                    return true;
                }
                finally
                {
                    CloseHandle(token);
                }
            }

            private static bool EnableImpersonatePrivilege(
                out IntPtr token,
                out TokenPrivileges previous)
            {
                previous = new TokenPrivileges();
                token = IntPtr.Zero;
                if (!OpenProcessToken(
                    GetCurrentProcess(),
                    TokenQuery | TokenAdjustPrivileges,
                    out token))
                {
                    return false;
                }

                Luid luid;
                if (!LookupPrivilegeValue(null, "SeImpersonatePrivilege", out luid))
                {
                    return false;
                }
                var requested = new TokenPrivileges
                {
                    PrivilegeCount = 1,
                    Privileges = new LuidAndAttributes
                    {
                        Luid = luid,
                        Attributes = SePrivilegeEnabled,
                    },
                };
                uint returnedLength;
                return AdjustTokenPrivileges(
                    token,
                    false,
                    ref requested,
                    Marshal.SizeOf(typeof(TokenPrivileges)),
                    out previous,
                    out returnedLength)
                    && Marshal.GetLastWin32Error() != 1300;
            }

            [StructLayout(LayoutKind.Sequential)]
            private struct Luid
            {
                public uint LowPart;
                public int HighPart;
            }

            [StructLayout(LayoutKind.Sequential)]
            private struct LuidAndAttributes
            {
                public Luid Luid;
                public uint Attributes;
            }

            [StructLayout(LayoutKind.Sequential)]
            private struct TokenPrivileges
            {
                public uint PrivilegeCount;
                public LuidAndAttributes Privileges;
            }

            [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
            private struct StartupInformation
            {
                public int Size;
                public string Reserved;
                public string Desktop;
                public string Title;
                public uint X;
                public uint Y;
                public uint XSize;
                public uint YSize;
                public uint XCountChars;
                public uint YCountChars;
                public uint FillAttribute;
                public uint Flags;
                public short ShowWindow;
                public short Reserved2;
                public IntPtr Reserved2Pointer;
                public IntPtr StandardInput;
                public IntPtr StandardOutput;
                public IntPtr StandardError;
            }

            [StructLayout(LayoutKind.Sequential)]
            private struct ProcessInformation
            {
                public IntPtr Process;
                public IntPtr Thread;
                public uint ProcessId;
                public uint ThreadId;
            }

            [DllImport("advapi32.dll", SetLastError = true)]
            private static extern bool AdjustTokenPrivileges(
                IntPtr token,
                bool disableAllPrivileges,
                ref TokenPrivileges newState,
                int bufferLength,
                out TokenPrivileges previousState,
                out uint returnLength);

            [DllImport("kernel32.dll")]
            private static extern bool CloseHandle(IntPtr handle);

            [DllImport("userenv.dll", SetLastError = true)]
            private static extern bool CreateEnvironmentBlock(
                out IntPtr environment,
                IntPtr token,
                bool inherit);

            [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            private static extern bool CreateProcessWithTokenW(
                IntPtr token,
                uint logonFlags,
                string applicationName,
                StringBuilder commandLine,
                uint creationFlags,
                IntPtr environment,
                string currentDirectory,
                ref StartupInformation startupInformation,
                out ProcessInformation processInformation);

            [DllImport("userenv.dll", SetLastError = true)]
            private static extern bool DestroyEnvironmentBlock(IntPtr environment);

            [DllImport("advapi32.dll", SetLastError = true)]
            private static extern bool DuplicateTokenEx(
                IntPtr existingToken,
                uint desiredAccess,
                IntPtr tokenAttributes,
                int impersonationLevel,
                int tokenType,
                out IntPtr newToken);

            [DllImport("kernel32.dll")]
            private static extern IntPtr GetCurrentProcess();

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool GetExitCodeProcess(IntPtr process, out int exitCode);

            [DllImport("user32.dll")]
            private static extern IntPtr GetShellWindow();

            [DllImport("advapi32.dll", SetLastError = true)]
            private static extern bool GetTokenInformation(
                IntPtr token,
                int informationClass,
                out int information,
                int informationLength,
                out uint returnLength);

            [DllImport("user32.dll", SetLastError = true)]
            private static extern uint GetWindowThreadProcessId(
                IntPtr window,
                out uint processId);

            [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            private static extern bool LookupPrivilegeValue(
                string systemName,
                string name,
                out Luid luid);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern IntPtr OpenProcess(
                uint desiredAccess,
                bool inheritHandle,
                uint processId);

            [DllImport("advapi32.dll", SetLastError = true)]
            private static extern bool OpenProcessToken(
                IntPtr process,
                uint desiredAccess,
                out IntPtr token);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
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
