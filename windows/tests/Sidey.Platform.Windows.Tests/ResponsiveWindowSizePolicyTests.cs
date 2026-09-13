using Sidey.Core.Overlay;

namespace Sidey.Platform.Windows.Tests;

public sealed class ResponsiveWindowSizePolicyTests
{
    private static readonly WindowsMonitorInfo s_qhd125Percent = new(
        "display-1",
        "display-1",
        new NativePixelRect(0, 0, 2560, 1600),
        new NativePixelRect(0, 0, 2560, 1540),
        120,
        true);

    [Fact]
    public void QhdSettingsSizeMatchesReferenceCaptureProportions()
    {
        ResponsiveWindowSize size = ResponsiveWindowSizePolicy.Calculate(
            s_qhd125Percent,
            SideyWindowKind.Settings);

        Assert.Equal(1280, size.Width);
        Assert.Equal(924, size.Height);
    }

    [Fact]
    public void QhdHistorySizeMatchesReferenceCaptureProportions()
    {
        ResponsiveWindowSize size = ResponsiveWindowSizePolicy.Calculate(
            s_qhd125Percent,
            SideyWindowKind.History);

        Assert.Equal(768, size.Width);
        Assert.Equal(770, size.Height);
    }

    [Fact]
    public void QhdOnboardingUsesTheMacSetupAssistantProportions()
    {
        ResponsiveWindowSize size = ResponsiveWindowSizePolicy.Calculate(
            s_qhd125Percent,
            SideyWindowKind.Onboarding);

        Assert.Equal(1300, size.Width);
        Assert.Equal(1000, size.Height);
    }

    [Fact]
    public void SmallWorkAreaIsKeptWithinScreenBounds()
    {
        WindowsMonitorInfo monitor = s_qhd125Percent with
        {
            MonitorPixels = new NativePixelRect(0, 0, 1024, 600),
            WorkAreaPixels = new NativePixelRect(0, 0, 1024, 560),
            Dpi = 96,
        };

        ResponsiveWindowSize size = ResponsiveWindowSizePolicy.Calculate(monitor, SideyWindowKind.Settings);

        Assert.InRange(size.Width, 1, 962);
        Assert.InRange(size.Height, 1, 526);
    }

    [Fact]
    public void MinimumSettingsSizeRemainsUsableAtMonitorScale()
    {
        ResponsiveWindowSize size = ResponsiveWindowSizePolicy.Minimum(s_qhd125Percent, SideyWindowKind.Settings);

        Assert.Equal(700, size.Width);
        Assert.Equal(650, size.Height);
    }

    [Fact]
    public void OnboardingUsesTheSameNarrowLayoutFloorAsSettings()
    {
        ResponsiveWindowSize settings = ResponsiveWindowSizePolicy.Minimum(
            s_qhd125Percent,
            SideyWindowKind.Settings);
        ResponsiveWindowSize onboarding = ResponsiveWindowSizePolicy.Minimum(
            s_qhd125Percent,
            SideyWindowKind.Onboarding);

        Assert.Equal(settings, onboarding);
    }

    [Fact]
    public void NativeTrackingConstraintClampsEachDimensionWithoutShrinkingTheOther()
    {
        var minimum = new ResponsiveWindowSize(700, 650);

        Assert.Equal(
            new ResponsiveWindowSize(900, 900),
            WindowsMinimumSizeController.ClampMinimumTrackSize(
                new ResponsiveWindowSize(900, 900),
                minimum));
        Assert.Equal(
            new ResponsiveWindowSize(1200, 700),
            WindowsMinimumSizeController.ClampMinimumTrackSize(
                new ResponsiveWindowSize(1200, 700),
                minimum));
    }
}
