namespace Sidey.Platform.Windows.Tests;

public sealed class StartupDiagnosticsSourceTests
{
    [Fact]
    public void SessionLogsUseOneUtcVersionedFileAcrossStartupAndRuntime()
    {
        string source = ReadRepositoryFile("windows", "src", "Sidey.App", "StartupDiagnostics.cs");
        string app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");

        Assert.Contains("SIDEY.{VersionToken()}.{timestamp:yyyyMMdd}.{timestamp:HHmmss}.log", source, StringComparison.Ordinal);
        Assert.Contains("DateTimeOffset.UtcNow", source, StringComparison.Ordinal);
        Assert.Contains("time-zone=UTC offset=+00:00", source, StringComparison.Ordinal);
        Assert.DoesNotContain("_logKind", source, StringComparison.Ordinal);
        Assert.Contains("StartupDiagnostics.MarkRunning();", app, StringComparison.Ordinal);
        Assert.Contains("StartupDiagnostics.CompleteSession();", app, StringComparison.Ordinal);
    }

    [Fact]
    public void SessionHeaderIncludesRuntimeContextWithoutMachineIdentity()
    {
        string source = ReadRepositoryFile("windows", "src", "Sidey.App", "StartupDiagnostics.cs");

        Assert.Contains("os-arch=", source, StringComparison.Ordinal);
        Assert.Contains("process-arch=", source, StringComparison.Ordinal);
        Assert.Contains("runtime=", source, StringComparison.Ordinal);
        Assert.Contains("processors=", source, StringComparison.Ordinal);
        Assert.DoesNotContain("MachineName", source, StringComparison.Ordinal);
        Assert.DoesNotContain("UserName", source, StringComparison.Ordinal);
    }

    [Fact]
    public void OverlayFailuresAndSuccessfulPresentationAreBothRecorded()
    {
        string app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");
        string coordinator = ReadRepositoryFile("windows", "src", "Sidey.App", "AppCoordinator.cs");
        string renderer = ReadRepositoryFile(
            "windows", "src", "Sidey.Overlay", "LayeredPixelWorldRenderer.cs");

        Assert.Contains("StartupDiagnostics.NonFatal(\"overlay-render\"", app, StringComparison.Ordinal);
        Assert.Contains("overlay-message-presented count=", coordinator, StringComparison.Ordinal);
        Assert.Contains("_surface.Present", renderer, StringComparison.Ordinal);
        Assert.Contains("ReportPresentedMessageBubbles();", renderer, StringComparison.Ordinal);
    }

    [Fact]
    public void LogRetentionIsBoundedByAgeSizeAndCount()
    {
        string source = ReadRepositoryFile("windows", "src", "Sidey.App", "StartupDiagnostics.cs");

        Assert.Contains("MaximumLogFileBytes = 4L * 1024 * 1024", source, StringComparison.Ordinal);
        Assert.Contains("MaximumLogDirectoryBytes = 32L * 1024 * 1024", source, StringComparison.Ordinal);
        Assert.Contains("MaximumLogFileCount = 100", source, StringComparison.Ordinal);
        Assert.Contains("TimeSpan.FromDays(30)", source, StringComparison.Ordinal);
        Assert.Contains("TimeSpan.FromHours(6)", source, StringComparison.Ordinal);
        Assert.Contains("file.LastWriteTimeUtc < retentionThreshold", source, StringComparison.Ordinal);
    }

    [Fact]
    public void DiagnosticsRecordHealthFailuresAndPrivacySafeNetworkCategories()
    {
        string source = ReadRepositoryFile("windows", "src", "Sidey.App", "StartupDiagnostics.cs");
        string app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");
        string coordinator = ReadRepositoryFile("windows", "src", "Sidey.App", "AppCoordinator.cs");
        string nativeSession = ReadRepositoryFile(
            "windows", "src", "Sidey.Overlay", "NativePixelWorldSession.cs");

        Assert.Contains("runtime-health working-set-bytes=", source, StringComparison.Ordinal);
        Assert.Contains("repeat={repeat}", source, StringComparison.Ordinal);
        Assert.Contains("previous-session-end result=unclean", source, StringComparison.Ordinal);
        Assert.Contains("category=tls", source, StringComparison.Ordinal);
        Assert.Contains("category=timeout", source, StringComparison.Ordinal);
        Assert.Contains("source-location-redacted", source, StringComparison.Ordinal);
        Assert.Contains("ui-heartbeat delay-ms=", app, StringComparison.Ordinal);
        Assert.Contains("auth-session-bootstrap-started", coordinator, StringComparison.Ordinal);
        Assert.Contains("renderer-health frames=", coordinator, StringComparison.Ordinal);
        Assert.Contains("overlay-environment monitor=", nativeSession, StringComparison.Ordinal);
        Assert.Contains("overlay-z-order mode=behind-shell", nativeSession, StringComparison.Ordinal);
        Assert.DoesNotContain("Environment.UserName", source, StringComparison.Ordinal);
        Assert.DoesNotContain("Environment.MachineName", source, StringComparison.Ordinal);
    }

    [Fact]
    public void CachedSettingsLoadBeforeTheSettingsWindowIsConstructed()
    {
        string app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");

        int loadCache = app.IndexOf("await _coordinator.LoadCachedStateAsync();", StringComparison.Ordinal);
        int createWindow = app.IndexOf("_mainWindow = new MainWindow(_coordinator);", StringComparison.Ordinal);

        Assert.True(loadCache >= 0, "The local settings cache must be loaded during launch.");
        Assert.True(createWindow > loadCache, "The settings window must start from cached values.");
    }

    [Fact]
    public void StartupUpdateAvailabilityPostsASystemNotification()
    {
        string app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");
        string tray = ReadRepositoryFile(
            "windows", "src", "Sidey.Platform.Windows", "TrayIconService.cs");
        string xaml = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml");

        Assert.Contains("CheckForUpdatesOnStartupAsync", app, StringComparison.Ordinal);
        Assert.Contains("_tray.NotifyUpdateAvailable(version)", app, StringComparison.Ordinal);
        Assert.Contains("public void NotifyUpdateAvailable", tray, StringComparison.Ordinal);
        Assert.Contains("CurrentVersionText", xaml, StringComparison.Ordinal);
        Assert.Contains("LastUpdateCheckText", xaml, StringComparison.Ordinal);
        Assert.Contains("OpenReleaseNotesCommand", xaml, StringComparison.Ordinal);
    }

    private static string ReadRepositoryFile(params string[] pathSegments) =>
        File.ReadAllText(RepositoryPath(pathSegments));

    private static string RepositoryPath(params string[] pathSegments)
    {
        var root = new DirectoryInfo(AppContext.BaseDirectory);
        while (root is not null && !Directory.Exists(Path.Combine(root.FullName, "windows", "src")))
        {
            root = root.Parent;
        }

        Assert.NotNull(root);
        return Path.Combine([root.FullName, .. pathSegments]);
    }
}
