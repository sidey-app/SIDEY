using Sidey.Core.Domain;
using Sidey.Core.Overlay;

namespace Sidey.Core.Tests;

public sealed class StarlightSparkleLayoutTests
{
    [Theory]
    [InlineData(OverlayEdge.Bottom, 110, 180)]
    [InlineData(OverlayEdge.Top, 90, 220)]
    [InlineData(OverlayEdge.Left, 120, 210)]
    [InlineData(OverlayEdge.Right, 80, 190)]
    public void AmbientUsesCharacterCenterAndPresentationRotation(OverlayEdge edge, double x, double y)
    {
        Assert.Equal((x, y), StarlightSparkleLayout.Point((100, 200), 10, 20, edge));
    }

    [Fact]
    public void IdleParticlesAreAboveCenterSpreadOutAndChangeEachCycle()
    {
        var particles = Enumerable.Range(0, 6)
            .Select(index => StarlightSparkleLayout.Ambient(0.525, index, 0x51DE59)).ToArray();
        Assert.All(particles, particle =>
        {
            Assert.InRange(particle.Tangent, -25, 25);
            Assert.InRange(particle.Normal, 7, 39);
            Assert.InRange(particle.Radius, 2.6, 4);
            Assert.Equal(1, particle.Opacity, 8);
        });
        Assert.True(particles.Max(p => p.Tangent) - particles.Min(p => p.Tangent) > 20);
        Assert.NotEqual(particles[0], StarlightSparkleLayout.Ambient(1.725, 0, 0x51DE59));
        Assert.Equal(0, StarlightSparkleLayout.Ambient(1.1, 0, 0x51DE59).Opacity);
    }
}
