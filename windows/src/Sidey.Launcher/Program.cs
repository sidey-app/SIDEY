using System;
using System.Diagnostics;
using System.IO;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

public static class Program
{
    private const string UninstallCleanupArgument = "--uninstall-cleanup";
    private const string CredentialFilter = "SIDEY/*";
    private const int ErrorNotFound = 1168;

    [STAThread]
    public static int Main(string[] arguments)
    {
        if (arguments.Length == 1
            && string.Equals(
                arguments[0],
                UninstallCleanupArgument,
                StringComparison.OrdinalIgnoreCase))
        {
            return RemoveCurrentUserData();
        }

        string deploymentRoot = AppDomain.CurrentDomain.BaseDirectory;
        string hostPath = Path.Combine(deploymentRoot, "Runtime", "SIDEY.Host.exe");
        if (!File.Exists(hostPath))
        {
            MessageBox(
                IntPtr.Zero,
                Localize(deploymentRoot, "runtimeMissing", "SIDEY Runtime\\SIDEY.Host.exe was not found. Reinstall SIDEY."),
                Localize(deploymentRoot, "fatalTitle", "SIDEY Startup Error"),
                0x10);
            return 2;
        }

        try
        {
            ProcessStartInfo start = new ProcessStartInfo();
            start.FileName = hostPath;
            // WinUI's PRI/XAML loader resolves app resources relative to the
            // real host directory, not the public launcher directory.
            start.WorkingDirectory = Path.GetDirectoryName(hostPath);
            start.UseShellExecute = false;
            start.Arguments = JoinArguments(arguments);
            Process.Start(start);
            return 0;
        }
        catch (Exception exception)
        {
            MessageBox(
                IntPtr.Zero,
                Localize(deploymentRoot, "startupFailed", "SIDEY could not start.")
                    + "\r\n\r\n" + exception.Message,
                Localize(deploymentRoot, "fatalTitle", "SIDEY Startup Error"),
                0x10);
            return 1;
        }
    }

    private static string Localize(string deploymentRoot, string name, string fallback)
    {
        try
        {
            string language = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "en"
                ? "en-US"
                : "ko-KR";
            string path = Path.Combine(deploymentRoot, "Langs", language + ".json");
            string json = File.ReadAllText(path, Encoding.UTF8);
            Match match = Regex.Match(
                json,
                "\\\"" + Regex.Escape(name) + "\\\"\\s*:\\s*\\\"((?:\\\\.|[^\\\"])*)\\\"");
            if (match.Success)
            {
                return Regex.Unescape(match.Groups[1].Value.Replace("\\/", "/"));
            }
        }
        catch
        {
            // The launcher must still report startup failures when catalogs are damaged.
        }

        return fallback;
    }

    private static string JoinArguments(string[] arguments)
    {
        StringBuilder commandLine = new StringBuilder();
        foreach (string argument in arguments)
        {
            if (commandLine.Length > 0)
            {
                commandLine.Append(' ');
            }
            commandLine.Append(QuoteArgument(argument));
        }
        return commandLine.ToString();
    }

    private static string QuoteArgument(string argument)
    {
        if (argument.Length > 0
            && argument.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) < 0)
        {
            return argument;
        }

        StringBuilder quoted = new StringBuilder();
        quoted.Append('"');
        int backslashes = 0;
        foreach (char character in argument)
        {
            if (character == '\\')
            {
                backslashes++;
                continue;
            }
            if (character == '"')
            {
                quoted.Append('\\', (backslashes * 2) + 1);
                quoted.Append('"');
                backslashes = 0;
                continue;
            }
            quoted.Append('\\', backslashes);
            backslashes = 0;
            quoted.Append(character);
        }
        quoted.Append('\\', backslashes * 2);
        quoted.Append('"');
        return quoted.ToString();
    }

    private static int RemoveCurrentUserData()
    {
        try
        {
            DeleteSideyCredentials();

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
            // Windows Installer records the non-zero exit code in its log and
            // reports the selected cleanup as failed instead of silently
            // preserving only part of the current user's data.
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
