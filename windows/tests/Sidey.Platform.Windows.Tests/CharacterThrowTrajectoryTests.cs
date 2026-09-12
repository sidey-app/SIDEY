using Sidey.Core.Domain;
using Sidey.Overlay;
using Sidey.Core.Overlay;

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
        foreach (int integerScale in new[] { 2, 3, 4 })
        {
            int size = 24 * integerScale;
            int baseline = 3 * integerScale;
            var content = new PixelContentBounds(baseline, baseline, size - baseline, size - baseline);
            (double X, double Y) center = LayeredPixelWorldRenderer.CharacterCenterPoint(
                (400d, 600d), size, baseline, content, edge);
            double inward = (size / 2d) - baseline;
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
        (double X, double Y) center = LayeredPixelWorldRenderer.CharacterCenterPoint(
            (400d, 600d), 48, 6, new PixelContentBounds(2, 6, 42, 44), edge);
        Assert.Equal((expectedX, 600d), center);
    }

}
