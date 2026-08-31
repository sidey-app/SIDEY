namespace Sidey.Platform.Windows.Tests;

public sealed class WindowPolicyTests
{
    private const uint Topmost = 0x00000008;
    private const uint Transparent = 0x00000020;
    private const uint ToolWindow = 0x00000080;
    private const uint Layered = 0x00080000;
    private const uint NoRedirectionBitmap = 0x00200000;
    private const uint NoActivate = 0x08000000;

    [Fact]
    public void WorldWindowIsLayeredClickThroughTopmostAndNonActivating()
    {
        var style = NativeOverlayWindow.ExtendedStyleBits(NativeOverlayWindowRole.World);

        AssertHas(style, Topmost);
        AssertHas(style, Transparent);
        AssertHas(style, ToolWindow);
        AssertHas(style, Layered);
        Assert.Equal(0u, style & NoRedirectionBitmap);
        AssertHas(style, NoActivate);
    }

    [Fact]
    public void HotspotReceivesInputButNeverActivatesOrAppearsInTaskSwitcher()
    {
        var style = NativeOverlayWindow.ExtendedStyleBits(NativeOverlayWindowRole.Hotspot);

        AssertHas(style, Topmost);
        AssertHas(style, ToolWindow);
        AssertHas(style, Layered);
        AssertHas(style, NoActivate);
        Assert.Equal(0u, style & Transparent);
        Assert.Equal(0u, style & NoRedirectionBitmap);
    }

    [Fact]
    public void ProductMinimumOsIsWindowsElevenTwentyFiveH2()
    {
        Assert.Equal(26200, WindowsVersionGuard.MinimumBuild);
    }

    [Theory]
    [InlineData(0, 0, 52, 52, true)]
    [InlineData(-100, -100, 52, 52, true)]
    [InlineData(0, 0, 0, 52, false)]
    [InlineData(0, 0, 52, -1, false)]
    public void PixelRectSupportsNegativeMonitorCoordinatesButRejectsEmptySize(
        int x,
        int y,
        int width,
        int height,
        bool expected)
    {
        Assert.Equal(expected, new NativePixelRect(x, y, width, height).IsValid);
    }

    private static void AssertHas(uint style, uint flag) => Assert.Equal(flag, style & flag);
}
