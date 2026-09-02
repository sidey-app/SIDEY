using Sidey.Core.Overlay;

namespace Sidey.Platform.Windows.Tests;

public sealed class ResponsiveWindowSizePolicyTests
{
    private static readonly WindowsMonitorInfo Qhd125Percent = new(
        "display-1",
        "display-1",
        new NativePixelRect(0, 0, 2560, 1600),
        new NativePixelRect(0, 0, 2560, 1540),
        120,
        true);

    [Fact]
    public void QhdSettingsSizeMatchesReferenceCaptureProportions()
    {
        var size = ResponsiveWindowSizePolicy.Calculate(
            Qhd125Percent,
            SideyWindowKind.Settings);

        Assert.Equal(1280, size.Width);
        Assert.Equal(924, size.Height);
    }

    [Fact]
    public void QhdHistorySizeMatchesReferenceCaptureProportions()
    {
        var size = ResponsiveWindowSizePolicy.Calculate(
            Qhd125Percent,
            SideyWindowKind.History);

        Assert.Equal(768, size.Width);
        Assert.Equal(770, size.Height);
    }

    [Fact]
    public void QhdOnboardingUsesTheMacSetupAssistantProportions()
    {
        var size = ResponsiveWindowSizePolicy.Calculate(
            Qhd125Percent,
            SideyWindowKind.Onboarding);

        Assert.Equal(1300, size.Width);
        Assert.Equal(1000, size.Height);
    }

    [Fact]
    public void SmallWorkAreaIsKeptWithinScreenBounds()
    {
        var monitor = Qhd125Percent with
        {
            MonitorPixels = new NativePixelRect(0, 0, 1024, 600),
            WorkAreaPixels = new NativePixelRect(0, 0, 1024, 560),
            Dpi = 96,
        };

        var size = ResponsiveWindowSizePolicy.Calculate(monitor, SideyWindowKind.Settings);

        Assert.InRange(size.Width, 1, 962);
        Assert.InRange(size.Height, 1, 526);
    }

    [Fact]
    public void MinimumSettingsSizeRemainsUsableAtMonitorScale()
    {
        var size = ResponsiveWindowSizePolicy.Minimum(Qhd125Percent, SideyWindowKind.Settings);

        Assert.Equal(800, size.Width);
        Assert.Equal(700, size.Height);
    }
}
