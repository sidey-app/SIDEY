using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace Sidey.App;

internal static class StartupDiagnostics
{
    private const long MaximumLogBytes = 256 * 1024;
    private static readonly object Gate = new();
    private static readonly string LogDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "SIDEY",
        "Logs");
    private static readonly string LogPath = Path.Combine(LogDirectory, "startup.log");
    private static int _fatalDialogShown;

    public static void BeginSession()
    {
        lock (Gate)
        {
            try
            {
                Directory.CreateDirectory(LogDirectory);
                if (File.Exists(LogPath) && new FileInfo(LogPath).Length > MaximumLogBytes)
                {
                    File.Move(
                        LogPath,
                        Path.Combine(LogDirectory, "startup.previous.log"),
                        overwrite: true);
                }
                AppendLine($"session-start version={AppVersion()} os={Environment.OSVersion.Version}");
            }
            catch
            {
                // Diagnostics must never become another startup failure.
            }
        }
    }

    public static void Stage(string name) => Write($"stage={name}");

    public static void NonFatal(string stage, Exception exception) =>
        WriteException("non-fatal", stage, exception);

    public static void Fatal(string stage, Exception exception, bool showDialog)
    {
        WriteException("fatal", stage, exception);
        if (showDialog)
        {
            ShowFatalDialog();
        }
    }

    private static void Write(string value)
    {
        lock (Gate)
        {
            try
            {
                Directory.CreateDirectory(LogDirectory);
                AppendLine(value);
            }
            catch
            {
                // Best-effort logging only.
            }
        }
    }

    private static void WriteException(string severity, string stage, Exception exception)
    {
        ArgumentNullException.ThrowIfNull(exception);
        var builder = new StringBuilder();
        var current = exception;
        for (var depth = 0; current is not null && depth < 8; depth++)
        {
            if (depth > 0)
            {
                builder.Append(" | inner=");
            }
            builder.Append(current.GetType().FullName);
            builder.Append(" hresult=0x");
            builder.Append(current.HResult.ToString("X8"));
            AppendSafeDetails(builder, current);
            if (!string.IsNullOrWhiteSpace(current.StackTrace))
            {
                builder.Append(" stack=");
                builder.Append(current.StackTrace.ReplaceLineEndings(" <- "));
            }
            current = current.InnerException;
        }
        Write($"{severity} stage={stage} exception={builder}");
    }

    private static void AppendSafeDetails(StringBuilder builder, Exception exception)
    {
        switch (exception)
        {
            case FileNotFoundException fileNotFound when fileNotFound.FileName is { } missingName:
                builder.Append(" file=");
                builder.Append(Path.GetFileName(missingName));
                break;
            case FileLoadException fileLoad when fileLoad.FileName is { } loadName:
                builder.Append(" file=");
                builder.Append(Path.GetFileName(loadName));
                break;
            case BadImageFormatException badImage when badImage.FileName is { } imageName:
                builder.Append(" file=");
                builder.Append(Path.GetFileName(imageName));
                break;
            case TypeInitializationException typeInitialization:
                builder.Append(" type=");
                builder.Append(typeInitialization.TypeName);
                break;
            case TypeLoadException typeLoad when typeLoad.TypeName is { } typeName:
                builder.Append(" type=");
                builder.Append(typeName);
                break;
            case Win32Exception win32:
                builder.Append(" native-error=");
                builder.Append(win32.NativeErrorCode);
                break;
        }
    }

    private static void AppendLine(string value) => File.AppendAllText(
        LogPath,
        $"{DateTimeOffset.UtcNow:O} pid={Environment.ProcessId} {value}{Environment.NewLine}",
        Encoding.UTF8);

    private static string AppVersion() =>
        typeof(App).Assembly.GetName().Version?.ToString() ?? "unknown";

    private static void ShowFatalDialog()
    {
        if (!OperatingSystem.IsWindows()
            || Interlocked.Exchange(ref _fatalDialogShown, 1) != 0)
        {
            return;
        }

        _ = NativeMethods.MessageBox(
            nint.Zero,
            $"SIDEY를 시작하지 못했습니다.\n\n진단 로그: {LogPath}",
            "SIDEY 시작 오류",
            0x00000010u | 0x00000000u);
    }

    private static class NativeMethods
    {
        [DllImport("user32.dll", EntryPoint = "MessageBoxW", CharSet = CharSet.Unicode)]
        public static extern int MessageBox(nint window, string text, string caption, uint type);
    }
}
