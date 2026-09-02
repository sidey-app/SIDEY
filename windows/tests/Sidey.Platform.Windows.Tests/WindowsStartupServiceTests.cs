namespace Sidey.Platform.Windows.Tests;

public sealed class WindowsStartupServiceTests
{
    [Theory]
    [InlineData("--background", true)]
    [InlineData("  --background  ", true)]
    [InlineData("--BACKGROUND", true)]
    [InlineData("", false)]
    [InlineData("--background --extra", false)]
    [InlineData(null, false)]
    public void BackgroundLaunchRequiresTheDedicatedStartupArgument(
        string? arguments,
        bool expected)
    {
        Assert.Equal(expected, WindowsStartupService.IsBackgroundLaunch(arguments));
    }

    [Fact]
    public void BackgroundLaunchStillShowsRequiredOnboardingButHidesCompletedSettings()
    {
        string source = File.ReadAllText(RepositoryPath(
            "windows", "src", "Sidey.App", "App.xaml.cs"));

        int onboardingBranch = source.IndexOf(
            "if (!_coordinator.State.Preferences.OnboardingCompleted)",
            StringComparison.Ordinal);
        int completedHidden = source.IndexOf(
            "StartupDiagnostics.Stage(\"completed-launch-window-hidden\")",
            StringComparison.Ordinal);

        Assert.True(onboardingBranch >= 0, "Incomplete onboarding must be handled first.");
        Assert.True(
            completedHidden > onboardingBranch,
            "Only an already-onboarded launch may start without a settings window.");
    }

    [Fact]
    public void StructuredRuntimeResolvesThePublicLauncher()
    {
        string root = Path.Combine(Path.GetTempPath(), "sidey-deployment-root");
        string runtime = Path.Combine(root, "Runtime");

        Assert.Equal(
            root,
            SideyDeploymentPaths.DeploymentRoot(
                Path.Combine(runtime, "SIDEY.Host.exe"),
                runtime));
        Assert.Equal(
            Path.Combine(root, "SIDEY.exe"),
            SideyDeploymentPaths.LauncherPath(
                Path.Combine(runtime, "SIDEY.Host.exe"),
                runtime));
    }

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
