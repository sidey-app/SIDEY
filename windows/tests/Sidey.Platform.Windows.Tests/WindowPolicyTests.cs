namespace Sidey.Platform.Windows.Tests;

using Sidey.Core.Domain;

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

    [Theory]
    [InlineData(OverlayEdge.Bottom, OverlaySpan.Full, -1920, 500, 1920, 300)]
    [InlineData(OverlayEdge.Top, OverlaySpan.Half, -1440, -200, 960, 300)]
    [InlineData(OverlayEdge.Left, OverlaySpan.Third, -1920, 133, 300, 333)]
    [InlineData(OverlayEdge.Right, OverlaySpan.Full, -300, -200, 300, 1000)]
    public void WindowsRegionLayoutUsesTopLeftPixelCoordinates(
        OverlayEdge edge,
        OverlaySpan span,
        int x,
        int y,
        int width,
        int height)
    {
        var workArea = new NativePixelRect(-1920, -200, 1920, 1000);

        var frame = WindowsOverlayRegionLayout.Frame(
            workArea,
            120,
            new OverlayRegionPreference(edge, span, null));

        Assert.Equal(new NativePixelRect(x, y, width, height), frame);
    }

    [Fact]
    public void AllTwelveWindowsPresetsStayInsideTheWorkAreaAndTouchTheSelectedEdge()
    {
        var workArea = new NativePixelRect(-1920, -200, 1920, 1000);

        foreach (var edge in Enum.GetValues<OverlayEdge>())
        {
            foreach (var span in Enum.GetValues<OverlaySpan>())
            {
                var frame = WindowsOverlayRegionLayout.Frame(
                    workArea,
                    120,
                    new OverlayRegionPreference(edge, span, null));

                Assert.True(frame.IsValid);
                Assert.InRange(frame.X, workArea.X, workArea.X + workArea.Width);
                Assert.InRange(frame.Y, workArea.Y, workArea.Y + workArea.Height);
                Assert.InRange(frame.X + frame.Width, workArea.X, workArea.X + workArea.Width);
                Assert.InRange(frame.Y + frame.Height, workArea.Y, workArea.Y + workArea.Height);

                if (edge is OverlayEdge.Bottom or OverlayEdge.Top)
                {
                    Assert.Equal(
                        Round(workArea.Width * span.Fraction()),
                        frame.Width);
                    Assert.Equal(300, frame.Height);
                    Assert.Equal(
                        edge == OverlayEdge.Top
                            ? workArea.Y
                            : workArea.Y + workArea.Height,
                        edge == OverlayEdge.Top ? frame.Y : frame.Y + frame.Height);
                }
                else
                {
                    Assert.Equal(300, frame.Width);
                    Assert.Equal(
                        Round(workArea.Height * span.Fraction()),
                        frame.Height);
                    Assert.Equal(
                        edge == OverlayEdge.Left
                            ? workArea.X
                            : workArea.X + workArea.Width,
                        edge == OverlayEdge.Left ? frame.X : frame.X + frame.Width);
                }
            }
        }
    }

    private static void AssertHas(uint style, uint flag) => Assert.Equal(flag, style & flag);

    private static int Round(double value) =>
        (int)Math.Round(value, MidpointRounding.AwayFromZero);
}
