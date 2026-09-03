using System.ComponentModel;
using System.Diagnostics;
using System.Net.Http;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Authentication;
using System.Text;
using System.Text.RegularExpressions;
using Sidey.Core.Localization;

namespace Sidey.App;

internal static class StartupDiagnostics
{
    private const long MaximumLogFileBytes = 4L * 1024 * 1024;
    private const long MaximumLogDirectoryBytes = 32L * 1024 * 1024;
    private const int MaximumLogFileCount = 100;
    private static readonly TimeSpan LogRetention = TimeSpan.FromDays(30);
    private static readonly TimeSpan CleanupInterval = TimeSpan.FromHours(6);
    private static readonly TimeSpan RuntimeHealthInterval = TimeSpan.FromMinutes(1);
    private static readonly object Gate = new();
    private static readonly Dictionary<string, int> ErrorRepeatCounts = new(StringComparer.Ordinal);
    private static readonly string LogDirectory = Path.Combine(
        Sidey.Core.Storage.SideyStoragePaths.LocalApplicationDataRoot(),
        "SIDEY",
        "Logs");
    private static string _logPath = string.Empty;
    private static DateTimeOffset _lastLogTimestamp = DateTimeOffset.MinValue;
    private static Timer? _cleanupTimer;
    private static Timer? _runtimeHealthTimer;
    private static int _fatalDialogShown;
    private static bool _logCapacityReached;

    public static void BeginSession()
    {
        lock (Gate)
        {
            try
            {
                Directory.CreateDirectory(LogDirectory);
                string? previousLogPath = FindPreviousSessionLog();
                _logPath = CreateLogPath();
                CleanupLogs();
                _cleanupTimer ??= new Timer(
                    CleanupOnTimer,
                    null,
                    CleanupInterval,
                    CleanupInterval);
                AppendLine(
                    $"session-start version={AppVersion()} build={BuildVersion()} "
                    + $"os={Environment.OSVersion.Version} "
                    + $"os-arch={RuntimeInformation.OSArchitecture.ToString().ToLowerInvariant()} "
                    + $"process-arch={RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant()} "
                    + $"runtime={RuntimeInformation.FrameworkDescription.Replace(' ', '_')} "
                    + $"processors={Environment.ProcessorCount} time-zone=UTC offset=+00:00");
                if (previousLogPath is not null && !EndedNormally(previousLogPath))
                {
                    AppendLine("previous-session-end result=unclean");
                }
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
                AppendLine("runtime-start");
                _runtimeHealthTimer ??= new Timer(
                    RecordRuntimeHealth,
                    null,
                    RuntimeHealthInterval,
                    RuntimeHealthInterval);
            }
            catch
            {
                // Diagnostics must never become another startup failure.
            }
        }
    }

    public static void CompleteSession()
    {
        lock (Gate)
        {
            try
            {
                AppendLine("shutdown-complete result=normal");
            }
            catch
            {
                // Diagnostics must never prevent shutdown.
            }
            finally
            {
                _runtimeHealthTimer?.Dispose();
                _runtimeHealthTimer = null;
                _cleanupTimer?.Dispose();
                _cleanupTimer = null;
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
                builder.Append(SanitizeStackTrace(current.StackTrace));
            }
            current = current.InnerException;
        }

        string repeatKey = $"{severity}:{stage}:{exception.GetType().FullName}:{exception.HResult:X8}";
        int repeat;
        lock (Gate)
        {
            repeat = ErrorRepeatCounts.GetValueOrDefault(repeatKey) + 1;
            ErrorRepeatCounts[repeatKey] = repeat;
        }
        Write($"{severity} stage={stage} repeat={repeat} exception={builder}");
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
            case HttpRequestException http:
                builder.Append(" category=http");
                if (http.StatusCode is { } statusCode)
                {
                    builder.Append(" status=");
                    builder.Append((int)statusCode);
                }
                break;
            case SocketException socket:
                builder.Append(" category=");
                builder.Append(IsDnsError(socket.SocketErrorCode) ? "dns" : "socket");
                builder.Append(" socket=");
                builder.Append(socket.SocketErrorCode);
                builder.Append(" native-error=");
                builder.Append(socket.NativeErrorCode);
                break;
            case AuthenticationException:
                builder.Append(" category=tls");
                break;
            case TimeoutException:
                builder.Append(" category=timeout");
                break;
            case TaskCanceledException:
                builder.Append(" category=timeout");
                break;
            case Win32Exception win32:
                builder.Append(" native-error=");
                builder.Append(win32.NativeErrorCode);
                break;
        }
    }

    private static bool IsDnsError(SocketError error) => error is
        SocketError.HostNotFound or SocketError.NoData or SocketError.TryAgain;

    private static string SanitizeStackTrace(string stackTrace) => Regex.Replace(
        stackTrace,
        @" in .*?:line \d+",
        " source-location-redacted",
        RegexOptions.CultureInvariant).ReplaceLineEndings(" <- ");

    private static void AppendLine(string value)
    {
        if (string.IsNullOrEmpty(_logPath) || _logCapacityReached)
        {
            return;
        }

        string line = $"{DateTimeOffset.UtcNow:O} pid={Environment.ProcessId} {value}{Environment.NewLine}";
        int lineBytes = Encoding.UTF8.GetByteCount(line);
        if (File.Exists(_logPath)
            && new FileInfo(_logPath).Length + lineBytes > MaximumLogFileBytes)
        {
            const string capacityLine = "log-capacity-reached further-events=discarded";
            string marker = $"{DateTimeOffset.UtcNow:O} pid={Environment.ProcessId} {capacityLine}{Environment.NewLine}";
            File.AppendAllText(_logPath, marker, Encoding.UTF8);
            _logCapacityReached = true;
            return;
        }

        File.AppendAllText(_logPath, line, Encoding.UTF8);
    }

    private static string CreateLogPath()
    {
        DateTimeOffset timestamp = DateTimeOffset.UtcNow;
        if (timestamp <= _lastLogTimestamp)
        {
            timestamp = _lastLogTimestamp.AddSeconds(1);
        }

        string path;
        do
        {
            path = Path.Combine(
                LogDirectory,
                $"SIDEY.{VersionToken()}.{timestamp:yyyyMMdd}.{timestamp:HHmmss}.log");
            timestamp = timestamp.AddSeconds(1);
        }
        while (File.Exists(path));

        _lastLogTimestamp = timestamp.AddSeconds(-1);
        return path;
    }

    private static string? FindPreviousSessionLog() => Directory
        .EnumerateFiles(LogDirectory, "SIDEY.*.log", SearchOption.TopDirectoryOnly)
        .OrderByDescending(File.GetLastWriteTimeUtc)
        .FirstOrDefault();

    private static bool EndedNormally(string path)
    {
        try
        {
            return File.ReadLines(path)
                .TakeLast(32)
                .Any(line => line.Contains(
                    "shutdown-complete result=normal",
                    StringComparison.Ordinal));
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

    private static void RecordRuntimeHealth(object? state)
    {
        _ = state;
        lock (Gate)
        {
            try
            {
                using Process process = Process.GetCurrentProcess();
                uint gdiObjects = OperatingSystem.IsWindows()
                    ? NativeMethods.GetGuiResources(process.Handle, 0)
                    : 0;
                uint userObjects = OperatingSystem.IsWindows()
                    ? NativeMethods.GetGuiResources(process.Handle, 1)
                    : 0;
                AppendLine(
                    $"runtime-health working-set-bytes={process.WorkingSet64} "
                    + $"private-bytes={process.PrivateMemorySize64} "
                    + $"managed-bytes={GC.GetTotalMemory(forceFullCollection: false)} "
                    + $"handles={process.HandleCount} gdi-objects={gdiObjects} user-objects={userObjects}");
            }
            catch
            {
                // Health diagnostics must remain best effort.
            }
        }
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
        typeof(App).Assembly.GetName().Version?.ToString(3) ?? "unknown";

    private static string BuildVersion() =>
        typeof(App).Assembly.GetCustomAttribute<AssemblyFileVersionAttribute>()?.Version
        ?? "unknown";

    private static string VersionToken() => AppVersion().Replace('.', '_');

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

        [DllImport("user32.dll")]
        public static extern uint GetGuiResources(nint process, uint flags);
    }
}
