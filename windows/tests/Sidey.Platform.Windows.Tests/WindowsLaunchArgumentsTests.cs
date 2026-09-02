namespace Sidey.Platform.Windows.Tests;

public sealed class WindowsLaunchArgumentsTests
{
    [Fact]
    public void ActivationArgumentsTakePriorityWhenWinUiProvidesThem()
    {
        string? resolved = WindowsLaunchArguments.Resolve(
            "--background",
            ["SIDEY.exe", "--onboarding-preview"]);

        Assert.Equal("--background", resolved);
    }

    [Fact]
    public void UnpackagedLaunchFallsBackToProcessCommandLine()
    {
        string? resolved = WindowsLaunchArguments.Resolve(
            string.Empty,
            ["SIDEY.exe", "--onboarding-preview"]);

        Assert.Equal("--onboarding-preview", resolved);
    }

    [Fact]
    public void OrdinaryLaunchHasNoSyntheticArguments()
    {
        Assert.Null(WindowsLaunchArguments.Resolve(null, ["SIDEY.exe"]));
    }
}
