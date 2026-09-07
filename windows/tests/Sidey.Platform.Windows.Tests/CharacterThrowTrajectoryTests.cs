using Sidey.Core.Domain;
using Sidey.Overlay;

namespace Sidey.Platform.Windows.Tests;

public sealed class CharacterThrowTrajectoryTests
{
    [Theory]
    [InlineData(OverlayEdge.Bottom, 0, -1)]
    [InlineData(OverlayEdge.Top, 0, 1)]
    [InlineData(OverlayEdge.Left, 1, 0)]
    [InlineData(OverlayEdge.Right, -1, 0)]
    public void LaunchUsesUnpulsedSpriteCenterInsteadOfFoot(OverlayEdge edge, int inwardX, int inwardY)
    {
        foreach (var integerScale in new[] { 2, 3, 4 })
        {
            var size = 24 * integerScale;
            var baseline = 3 * integerScale;
            var content = new PixelContentBounds(baseline, baseline, size - baseline, size - baseline);
            var center = LayeredPixelWorldRenderer.CharacterCenterPoint(
                (400d, 600d), size, baseline, content, edge);
            var inward = (size / 2d) - baseline;
            Assert.Equal(400d + (inwardX * inward), center.X);
            Assert.Equal(600d + (inwardY * inward), center.Y);
            var flight = new CharacterThrowTrajectory(center, (800d, 600d), 1d);
            Assert.Equal(center, flight.PointAt((800d, 600d), 0d, edge));
        }
    }

    [Theory]
    [InlineData(OverlayEdge.Left, 422d)]
    [InlineData(OverlayEdge.Right, 382d)]
    public void SideAnchorUsesActualSpriteContentBounds(OverlayEdge edge, double expectedX)
    {
        var center = LayeredPixelWorldRenderer.CharacterCenterPoint(
            (400d, 600d), 48, 6, new PixelContentBounds(2, 6, 42, 44), edge);
        Assert.Equal((expectedX, 600d), center);
    }

    [Theory]
    [InlineData(1d)]
    [InlineData(1.25d)]
    [InlineData(1.5d)]
    [InlineData(2d)]
    public void FlightTimingAndArcMatchMacOsInLogicalPointsAtEveryDpi(double dpiScale)
    {
        foreach (var (distance, duration, arc) in new[]
        {
            (0d, 0.35d, 24d),
            (100d, 0.4125d, 24d),
            (400d, 0.6d, 72d),
            (1600d, 0.95d, 96d),
        })
        {
            var flight = new CharacterThrowTrajectory((0d, 100d * dpiScale), (distance * dpiScale, 100d * dpiScale), dpiScale);
            Assert.Equal(duration, flight.DurationSeconds, 10);
            Assert.Equal(arc * dpiScale, flight.ArcHeightPixels, 10);
            var midpoint = flight.PointAt((distance * dpiScale, 100d * dpiScale), duration / 2d, OverlayEdge.Bottom);
            Assert.Equal(distance / 2d, midpoint.X / dpiScale, 10);
            // A quadratic control-point offset contributes half its height at t = 0.5.
            Assert.Equal(100d - (arc / 2d), midpoint.Y / dpiScale, 10);
        }
    }

    [Theory]
    [InlineData(OverlayEdge.Bottom, 300d, 264d)]
    [InlineData(OverlayEdge.Top, 300d, 336d)]
    [InlineData(OverlayEdge.Left, 336d, 300d)]
    [InlineData(OverlayEdge.Right, 264d, 300d)]
    public void ArcBendsTowardScreenInterior(OverlayEdge edge, double expectedX, double expectedY)
    {
        var start = edge is OverlayEdge.Bottom or OverlayEdge.Top ? (100d, 300d) : (300d, 100d);
        var end = edge is OverlayEdge.Bottom or OverlayEdge.Top ? (500d, 300d) : (300d, 500d);
        var flight = new CharacterThrowTrajectory(start, end, 1d);
        Assert.Equal((expectedX, expectedY), flight.PointAt(end, flight.DurationSeconds / 2d, edge));
        Assert.Equal(start, flight.PointAt(end, -0.1d, edge));
        Assert.Equal(end, flight.PointAt(end, flight.DurationSeconds + 0.1d, edge));
    }

    [Fact]
    public void MovingTargetDoesNotChangeLaunchPointDurationOrArc()
    {
        var flight = new CharacterThrowTrajectory((100d, 300d), (500d, 300d), 1d);
        var movedEnd = (900d, 300d);
        Assert.Equal((100d, 300d), flight.PointAt(movedEnd, 0d, OverlayEdge.Bottom));
        Assert.Equal((500d, 264d), flight.PointAt(movedEnd, 0.3d, OverlayEdge.Bottom));
        Assert.Equal(movedEnd, flight.PointAt(movedEnd, 0.6d, OverlayEdge.Bottom));
        Assert.Equal(0.6d, flight.DurationSeconds);
        Assert.Equal(72d, flight.ArcHeightPixels);
    }
}
