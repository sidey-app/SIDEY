using Sidey.Core.Domain;
using Sidey.Core.Overlay;

namespace Sidey.Core.Tests;

public sealed class CharacterNameplateLayoutTests
{
    [Theory]
    [InlineData(OverlayEdge.Bottom)]
    [InlineData(OverlayEdge.Top)]
    [InlineData(OverlayEdge.Left)]
    [InlineData(OverlayEdge.Right)]
    public void DifferentNameLengthsKeepTheSameDistanceFromTheFoot(OverlayEdge edge)
    {
        foreach (int scale in new[] { 1, 2, 3, 4, 5 })
            foreach (int width in new[] { 35, 70, 140 })
            {
                const double height = 20;
                var position = CharacterNameplateLayout.Position((300, 400), width, height, scale, edge);
                double distance = edge switch
                {
                    OverlayEdge.Bottom => 400 - position.Y - height,
                    OverlayEdge.Top => position.Y - 400,
                    OverlayEdge.Left => position.X - 300,
                    _ => 300 - position.X - width,
                };
                Assert.Equal(22 * scale, distance);
                Assert.Equal(edge is OverlayEdge.Bottom or OverlayEdge.Top ? 300 : 400,
                    edge is OverlayEdge.Bottom or OverlayEdge.Top ? position.X + width / 2d : position.Y + height / 2d);
            }
    }

    [Theory]
    [InlineData(OverlayEdge.Bottom)]
    [InlineData(OverlayEdge.Top)]
    [InlineData(OverlayEdge.Left)]
    [InlineData(OverlayEdge.Right)]
    public void EveryStunFrameFitsBeforeTheFixedNameplate(OverlayEdge edge)
    {
        foreach (int scale in new[] { 1, 2, 3, 4, 5 })
        {
            var label = CharacterNameplateLayout.Position((0, 0), 140, 20, scale, edge);
            foreach (var frame in Enumerable.Range(0, 36))
                foreach (var pixel in CharacterStunPixels.Create(frame / 30d, true))
                {
                    // The sprite's three-pixel foot inset leaves 21px of canvas above the foot.
                    double inward = (21 - pixel.Y) * scale;
                    bool separated = edge switch
                    {
                        OverlayEdge.Bottom => -inward >= label.Y + 20,
                        OverlayEdge.Top => inward <= label.Y,
                        OverlayEdge.Left => inward <= label.X,
                        _ => -inward >= label.X + 140,
                    };
                    Assert.True(separated);
                }
        }
    }
}
