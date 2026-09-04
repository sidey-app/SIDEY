namespace Sidey.Platform.Windows.Tests;

public sealed class WindowsActivityMonitorSourceTests
{
    [Fact]
    public void DefaultPresenceSampleIntervalIsOneSecond()
    {
        var source = File.ReadAllText(Path.Combine(
            RepositoryRoot(),
            "windows",
            "src",
            "Sidey.Platform.Windows",
            "WindowsActivityMonitor.cs"));

        Assert.Contains(
            "sampleInterval ?? TimeSpan.FromSeconds(1)",
            source,
            StringComparison.Ordinal);
    }

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
