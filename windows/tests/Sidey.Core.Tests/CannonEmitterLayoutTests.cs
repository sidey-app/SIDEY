using Sidey.Core.Domain;
using Sidey.Core.Overlay;

namespace Sidey.Core.Tests;

public sealed class CannonEmitterLayoutTests
{
    [Theory]
    [InlineData(OverlayEdge.Bottom, false, 106, 201)]
    [InlineData(OverlayEdge.Bottom, true, 94, 201)]
    [InlineData(OverlayEdge.Top, false, 94, 199)]
    [InlineData(OverlayEdge.Top, true, 106, 199)]
    [InlineData(OverlayEdge.Left, false, 99, 206)]
    [InlineData(OverlayEdge.Left, true, 99, 194)]
    [InlineData(OverlayEdge.Right, false, 101, 194)]
    [InlineData(OverlayEdge.Right, true, 101, 206)]
    public void CenterMatchesMacOffsetAfterEdgeRotation(OverlayEdge edge, bool mirrored, double x, double y)
    {
        foreach (double scale in new[] { 1d, 1.5, 2d })
            Assert.Equal((x * scale, y * scale),
                CannonEmitterLayout.Center((100 * scale, 200 * scale), mirrored, edge, scale));
    }

    [Theory]
    [InlineData(OverlayEdge.Bottom)]
    [InlineData(OverlayEdge.Top)]
    [InlineData(OverlayEdge.Left)]
    [InlineData(OverlayEdge.Right)]
    public void EmitterIsInFrontOfActorTowardsTargetOnEveryEdge(OverlayEdge edge)
    {
        foreach (double target in new[] { 50d, 150d })
        {
            bool mirrored = CannonEmitterLayout.ShouldMirror(100, target, edge);
            (double X, double Y) center = CannonEmitterLayout.Center((100, 100), mirrored, edge, 1);
            double tangent = edge is OverlayEdge.Bottom or OverlayEdge.Top ? center.X : center.Y;
            Assert.Equal(Math.Sign(target - 100), Math.Sign(tangent - 100));
        }
    }
}
