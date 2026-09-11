using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;
using Sidey.Installer;

public static class Program
{
    private const string LanguageEnvironmentVariable = "SIDEY_LANGUAGE";
    private const string InstallerRegistryPath = @"Software\SIDEY\Installer";

    [STAThread]
    public static int Main(string[] arguments)
    {
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
            string language = ResolveLanguage(ResolveRequestedLanguage());
            var start = new ProcessStartInfo
            {
                FileName = hostPath,
                // WinUI's PRI/XAML loader resolves app resources relative to the
                // real host directory, not the public launcher directory.
                WorkingDirectory = Path.GetDirectoryName(hostPath),
                UseShellExecute = false,
                Arguments = JoinArguments(arguments),
            };
            start.EnvironmentVariables[LanguageEnvironmentVariable] = language;
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
            string requested = ResolveRequestedLanguage();
            string language = ResolveLanguage(requested);
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

    private static string ResolveRequestedLanguage()
    {
        string explicitLanguage = Environment.GetEnvironmentVariable(LanguageEnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(explicitLanguage))
        {
            return explicitLanguage;
        }

        try
        {
            using (RegistryKey machine = RegistryKey.OpenBaseKey(
                RegistryHive.LocalMachine,
                RegistryView.Registry64))
            using (RegistryKey installer = machine.OpenSubKey(InstallerRegistryPath, writable: false))
            {
                object savedValue = installer == null ? null : installer.GetValue("Language");
                int installerLanguage;
                if (int.TryParse(
                    Convert.ToString(savedValue, CultureInfo.InvariantCulture),
                    NumberStyles.Integer,
                    CultureInfo.InvariantCulture,
                    out installerLanguage))
                {
                    string appLanguage = InstallerLanguages.AppLanguage(installerLanguage);
                    if (!string.IsNullOrWhiteSpace(appLanguage))
                    {
                        return appLanguage;
                    }
                }
            }
        }
        catch
        {
            // A damaged or inaccessible installer key must not prevent launch.
        }

        return CultureInfo.CurrentUICulture.Name;
    }

    private static string ResolveLanguage(string requested)
    {
        if (requested.StartsWith("en", StringComparison.OrdinalIgnoreCase))
            return "en-US";
        if (requested.StartsWith("ja", StringComparison.OrdinalIgnoreCase))
            return "ja-JP";
        if (requested.StartsWith("zh-Hant", StringComparison.OrdinalIgnoreCase)
            || requested.StartsWith("zh-TW", StringComparison.OrdinalIgnoreCase)
            || requested.StartsWith("zh-HK", StringComparison.OrdinalIgnoreCase)
            || requested.StartsWith("zh-MO", StringComparison.OrdinalIgnoreCase))
            return "zh-TW";
        if (requested.StartsWith("zh", StringComparison.OrdinalIgnoreCase))
            return "zh-CN";
        if (requested.StartsWith("uk", StringComparison.OrdinalIgnoreCase))
            return "uk-UA";
        if (requested.StartsWith("ru", StringComparison.OrdinalIgnoreCase))
            return "ru-RU";

        return "ko-KR";
    }

    private static string JoinArguments(string[] arguments)
    {
        var commandLine = new StringBuilder();
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

        var quoted = new StringBuilder();
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

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBox(
        IntPtr window,
        string text,
        string caption,
        uint type);
}
