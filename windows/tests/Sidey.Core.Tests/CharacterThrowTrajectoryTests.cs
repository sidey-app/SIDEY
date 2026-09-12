using Sidey.Core.Domain;
using Sidey.Core.Overlay;

namespace Sidey.Core.Tests;

public sealed class CharacterThrowTrajectoryTests
{
    [Theory]
    [InlineData(1d)]
    [InlineData(1.25d)]
    [InlineData(1.5d)]
    [InlineData(2d)]
    public void FlightTimingAndArcMatchMacOsInLogicalPointsAtEveryDpi(double dpiScale)
    {
        foreach ((double distance, double duration, double arc) in new[]
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
            (double X, double Y) midpoint = flight.PointAt((distance * dpiScale, 100d * dpiScale), duration / 2d, OverlayEdge.Bottom);
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
        (double, double) start = edge is OverlayEdge.Bottom or OverlayEdge.Top ? (100d, 300d) : (300d, 100d);
        (double, double) end = edge is OverlayEdge.Bottom or OverlayEdge.Top ? (500d, 300d) : (300d, 500d);
        var flight = new CharacterThrowTrajectory(start, end, 1d);
        Assert.Equal((expectedX, expectedY), flight.PointAt(end, flight.DurationSeconds / 2d, edge));
        Assert.Equal(start, flight.PointAt(end, -0.1d, edge));
        Assert.Equal(end, flight.PointAt(end, flight.DurationSeconds + 0.1d, edge));
    }

    [Fact]
    public void MovingTargetDoesNotChangeLaunchPointDurationOrArc()
    {
        var flight = new CharacterThrowTrajectory((100d, 300d), (500d, 300d), 1d);
        (double, double) movedEnd = (900d, 300d);
        Assert.Equal((100d, 300d), flight.PointAt(movedEnd, 0d, OverlayEdge.Bottom));
        Assert.Equal((500d, 264d), flight.PointAt(movedEnd, 0.3d, OverlayEdge.Bottom));
        Assert.Equal(movedEnd, flight.PointAt(movedEnd, 0.6d, OverlayEdge.Bottom));
        Assert.Equal(0.6d, flight.DurationSeconds);
        Assert.Equal(72d, flight.ArcHeightPixels);
    }
}
