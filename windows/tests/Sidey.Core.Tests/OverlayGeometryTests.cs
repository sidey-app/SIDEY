using Sidey.Core.Domain;
using Sidey.Core.Overlay;

namespace Sidey.Core.Tests;

public sealed class OverlayGeometryTests
{
    public static IEnumerable<object[]> RegionPresets()
    {
        foreach (var edge in Enum.GetValues<OverlayEdge>())
        {
            foreach (var span in Enum.GetValues<OverlaySpan>())
            {
                yield return [edge, span];
            }
        }
    }

    [Theory]
    [MemberData(nameof(RegionPresets))]
    public void AllTwelvePresetsStayInsideWorkArea(OverlayEdge edge, OverlaySpan span)
    {
        var workArea = new RectD(100, 50, 1_920, 1_040);

        var frame = OverlayRegionLayout.Frame(new OverlayRegionPreference(edge, span, null), workArea);

        Assert.InRange(frame.MinX, workArea.MinX, workArea.MaxX);
        Assert.InRange(frame.MaxX, workArea.MinX, workArea.MaxX);
        Assert.InRange(frame.MinY, workArea.MinY, workArea.MaxY);
        Assert.InRange(frame.MaxY, workArea.MinY, workArea.MaxY);
        if (edge is OverlayEdge.Bottom or OverlayEdge.Top)
        {
            Assert.Equal(workArea.Width * span.Fraction(), frame.Width, 8);
            Assert.Equal(240d, frame.Height, 8);
        }
        else
        {
            Assert.Equal(240d, frame.Width, 8);
            Assert.Equal(workArea.Height * span.Fraction(), frame.Height, 8);
        }
    }

    [Fact]
    public void DepthCapsAtOneThirdOfShortWorkArea()
    {
        var frame = OverlayRegionLayout.Frame(
            OverlayRegionPreference.Default,
            new RectD(0, 0, 600, 300));

        Assert.Equal(100d, frame.Height);
    }

    [Fact]
    public void MissingMonitorFallsBackToPrimary()
    {
        var secondary = new MonitorGeometry("secondary", "보조", new RectD(0, 0, 800, 600), 96, false);
        var primary = new MonitorGeometry("primary", "주", new RectD(800, 0, 1_920, 1_040), 144, true);

        var selected = OverlayRegionLayout.SelectMonitor(
            new OverlayRegionPreference(OverlayEdge.Bottom, OverlaySpan.Full, "gone"),
            [secondary, primary]);

        Assert.Equal(primary, selected);
    }

    [Theory]
    [InlineData(96u, 2)]
    [InlineData(120u, 3)]
    [InlineData(144u, 3)]
    [InlineData(192u, 4)]
    public void PixelScaleIsIntegerAndRoundsMidpointsAwayFromZero(uint dpi, int expected)
    {
        Assert.Equal(expected, PixelScalePolicy.IntegerScale(dpi));
    }

    [Fact]
    public void FootTouchesEverySelectedScreenEdge()
    {
        foreach (var edge in Enum.GetValues<OverlayEdge>())
        {
            var bounds = edge is OverlayEdge.Bottom or OverlayEdge.Top
                ? new RectD(0, 0, 800, 240)
                : new RectD(0, 0, 240, 800);
            var geometry = new EdgeTrackGeometry(bounds, edge);
            var foot = geometry.FootPointFor(geometry.TrackLowerBound);

            switch (edge)
            {
                case OverlayEdge.Bottom:
                    Assert.Equal(bounds.MinY, foot.Y, 8);
                    break;
                case OverlayEdge.Top:
                    Assert.Equal(bounds.MaxY, foot.Y, 8);
                    break;
                case OverlayEdge.Left:
                    Assert.Equal(bounds.MinX, foot.X, 8);
                    break;
                case OverlayEdge.Right:
                    Assert.Equal(bounds.MaxX, foot.X, 8);
                    break;
                default:
                    throw new ArgumentOutOfRangeException();
            }
        }
    }
}
