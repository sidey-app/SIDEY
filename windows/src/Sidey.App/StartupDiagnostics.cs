using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Sidey.Core.Localization;

namespace Sidey.App;

internal static class StartupDiagnostics
{
    private const long MaximumLogFileBytes = 4L * 1024 * 1024;
    private const long MaximumLogDirectoryBytes = 32L * 1024 * 1024;
    private const int MaximumLogFileCount = 100;
    private static readonly TimeSpan LogRetention = TimeSpan.FromDays(30);
    private static readonly TimeSpan CleanupInterval = TimeSpan.FromHours(6);
    private static readonly object Gate = new();
    private static readonly string LogDirectory = Path.Combine(
        Sidey.Core.Storage.SideyStoragePaths.LocalApplicationDataRoot(),
        "SIDEY",
        "Logs");
    private static string _logKind = "startup";
    private static string _logPath = CreateLogPath(_logKind);
    private static DateTime _lastLogTimestamp = DateTime.MinValue;
    private static Timer? _cleanupTimer;
    private static int _fatalDialogShown;

    public static void BeginSession()
    {
        lock (Gate)
        {
            try
            {
                Directory.CreateDirectory(LogDirectory);
                CleanupLogs();
                _cleanupTimer ??= new Timer(
                    CleanupOnTimer,
                    null,
                    CleanupInterval,
                    CleanupInterval);
                AppendLine(
                    $"session-start version={AppVersion()} os={Environment.OSVersion.Version} "
                    + $"os-arch={RuntimeInformation.OSArchitecture.ToString().ToLowerInvariant()} "
                    + $"process-arch={RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant()} "
                    + $"runtime={RuntimeInformation.FrameworkDescription.Replace(' ', '_')} "
                    + $"processors={Environment.ProcessorCount}");
            }
            catch
            {
                // Diagnostics must never become another startup failure.
            }
        }
    }

    public static void MarkRunning()
    {
        lock (Gate)
        {
            try
            {
                AppendLine("startup-complete");
                _logKind = "running";
                _logPath = CreateLogPath(_logKind);
                AppendLine("runtime-start");
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

    private static void AppendLine(string value)
    {
        string line = $"{DateTimeOffset.UtcNow:O} pid={Environment.ProcessId} {value}{Environment.NewLine}";
        int lineBytes = Encoding.UTF8.GetByteCount(line);
        if (File.Exists(_logPath)
            && new FileInfo(_logPath).Length + lineBytes > MaximumLogFileBytes)
        {
            _logPath = CreateLogPath(_logKind);
            CleanupLogs();
        }

        File.AppendAllText(_logPath, line, Encoding.UTF8);
    }

    private static string CreateLogPath(string kind)
    {
        DateTime timestamp = DateTime.Now;
        if (timestamp <= _lastLogTimestamp)
        {
            timestamp = _lastLogTimestamp.AddMilliseconds(1);
        }

        _lastLogTimestamp = timestamp;
        return Path.Combine(LogDirectory, $"{timestamp:yyyyMMdd-HHmmssfff}-{kind}.log");
    }

    private static void CleanupOnTimer(object? state)
    {
        _ = state;
        lock (Gate)
        {
            try
            {
                CleanupLogs();
            }
            catch
            {
                // Retention cleanup is best effort.
            }
        }
    }

    private static void CleanupLogs()
    {
        if (!Directory.Exists(LogDirectory))
        {
            return;
        }

        DateTime retentionThreshold = DateTime.UtcNow - LogRetention;
        foreach (FileInfo expired in LogFiles()
                     .Where(file => file.LastWriteTimeUtc < retentionThreshold))
        {
            DeleteLog(expired);
        }

        FileInfo[] retained = LogFiles()
            .OrderBy(file => file.LastWriteTimeUtc)
            .ToArray();
        long totalBytes = retained.Sum(file => file.Length);
        int fileCount = retained.Length;
        foreach (FileInfo candidate in retained)
        {
            if (fileCount <= MaximumLogFileCount && totalBytes <= MaximumLogDirectoryBytes)
            {
                break;
            }

            if (StringComparer.OrdinalIgnoreCase.Equals(candidate.FullName, _logPath))
            {
                continue;
            }

            long length = candidate.Length;
            if (DeleteLog(candidate))
            {
                fileCount--;
                totalBytes -= length;
            }
        }
    }

    private static IEnumerable<FileInfo> LogFiles() =>
        new DirectoryInfo(LogDirectory).EnumerateFiles("*.log", SearchOption.TopDirectoryOnly);

    private static bool DeleteLog(FileInfo file)
    {
        if (StringComparer.OrdinalIgnoreCase.Equals(file.FullName, _logPath))
        {
            return false;
        }

        try
        {
            file.Delete();
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

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
            I18n.Format("error.startupWithLog", _logPath),
            I18n.Get("error.fatalTitle"),
            0x00000010u | 0x00000000u);
    }

    private static class NativeMethods
    {
        [DllImport("user32.dll", EntryPoint = "MessageBoxW", CharSet = CharSet.Unicode)]
        public static extern int MessageBox(nint window, string text, string caption, uint type);
    }
}
