using System;
using System.Diagnostics;
using System.IO;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

public static class Program
{
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

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBox(
        IntPtr window,
        string text,
        string caption,
        uint type);
}
