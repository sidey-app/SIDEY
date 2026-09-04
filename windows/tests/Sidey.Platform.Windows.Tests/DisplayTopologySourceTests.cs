namespace Sidey.Platform.Windows.Tests;

public sealed class DisplayTopologySourceTests
{
    [Fact]
    public void DisplayChangesAreDebouncedBeforeRefreshingOverlayGeometry()
    {
        string tray = ReadRepositoryFile(
            "windows", "src", "Sidey.Platform.Windows", "TrayIconService.cs");
        string app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");
        string coordinator = ReadRepositoryFile(
            "windows", "src", "Sidey.App", "AppCoordinator.cs");

        Assert.Contains("message == 0x007E", tray, StringComparison.Ordinal);
        Assert.Contains("DisplayTopologyChanged?.Invoke()", tray, StringComparison.Ordinal);
        Assert.Contains("DisplayTopologyRefreshDelay = TimeSpan.FromMilliseconds(500)", app, StringComparison.Ordinal);
        Assert.Contains("_coordinator.RefreshDisplayTopology();", app, StringComparison.Ordinal);
        Assert.Contains("IReadOnlyList<MonitorOption> monitors = GetMonitors();", coordinator, StringComparison.Ordinal);
        Assert.Contains("RestartOverlayForRegionChange();", coordinator, StringComparison.Ordinal);
    }

    private static string ReadRepositoryFile(params string[] parts) =>
        File.ReadAllText(Path.Combine([RepositoryRoot(), .. parts]));

    private static string RepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null
            && !Directory.Exists(Path.Combine(directory.FullName, "windows", "src")))
        {
            directory = directory.Parent;
        }

        return directory?.FullName
            ?? throw new DirectoryNotFoundException("Could not locate the SIDEY repository root.");
    }
}
