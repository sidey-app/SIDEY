using Sidey.Core.Domain;
using Sidey.Overlay;

namespace Sidey.Platform.Windows.Tests;

public sealed class OverlayBehaviorPolicyTests
{
    [Fact]
    public void ExistingPulseDoesNotReplayAfterWorldIsRecreated()
    {
        var pulse = Pulse();
        var guard = new CharacterPulseReplayGuard();

        guard.SeedExisting([pulse]);

        Assert.False(guard.TryAccept(pulse));
        Assert.True(guard.TryAccept(Pulse()));
    }

    [Fact]
    public void ExistingThrowDoesNotReplayAndGuardIsBounded()
    {
        var existing = Throw();
        var guard = new CharacterThrowReplayGuard(capacity: 2);

        guard.SeedExisting([existing]);
        Assert.False(guard.TryAccept(existing));
        var second = Throw();
        var third = Throw();
        Assert.True(guard.TryAccept(second));
        Assert.True(guard.TryAccept(third));
        Assert.True(guard.TryAccept(existing));
    }

    [Fact]
    public void PlacementSessionEntropyChangesInitialPositions()
    {
        var memberId = Guid.Parse("5ec7a319-2dde-48df-af96-e2554fc0cf2a");
        var firstSeed = OverlayPlacementPolicy.CombineSeed(1234, 10);
        var secondSeed = OverlayPlacementPolicy.CombineSeed(1234, 11);

        Assert.NotEqual(
            OverlayPlacementPolicy.Fraction(memberId, firstSeed),
            OverlayPlacementPolicy.Fraction(memberId, secondSeed));
        Assert.NotEqual(
            OverlayPlacementPolicy.Fraction(memberId, firstSeed),
            OverlayPlacementPolicy.Fraction(
                memberId,
                firstSeed,
                OverlayPlacementPolicy.TargetSalt));
    }

    [Theory]
    [InlineData(OverlayEdge.Left, 3, 2, new byte[] { 5, 3, 1, 6, 4, 2 })]
    [InlineData(OverlayEdge.Right, 3, 2, new byte[] { 2, 4, 6, 1, 3, 5 })]
    [InlineData(OverlayEdge.Top, 2, 3, new byte[] { 6, 5, 4, 3, 2, 1 })]
    public void TextVisualsRotateWithTheCharacter(
        OverlayEdge edge,
        int expectedWidth,
        int expectedHeight,
        byte[] expectedBlueValues)
    {
        var oriented = PixelVisualOrientation.Apply(Visual(2, 3), edge);

        Assert.Equal(expectedWidth, oriented.Width);
        Assert.Equal(expectedHeight, oriented.Height);
        Assert.Equal(expectedBlueValues, BlueValues(oriented));
    }

    private static CharacterPulseEvent Pulse() => new(
        Guid.NewGuid(),
        Guid.NewGuid(),
        Guid.NewGuid());

    private static CharacterThrowEvent Throw() => new(
        Guid.NewGuid(),
        Guid.NewGuid(),
        Guid.NewGuid(),
        Guid.NewGuid(),
        "pixel_hamster");

    private static PremultipliedVisual Visual(int width, int height)
    {
        var pixels = new byte[width * height * 4];
        for (var pixel = 0; pixel < width * height; pixel++)
        {
            pixels[pixel * 4] = (byte)(pixel + 1);
            pixels[(pixel * 4) + 3] = 255;
        }
        return new PremultipliedVisual(pixels, width, height);
    }

    private static byte[] BlueValues(PremultipliedVisual visual) =>
        Enumerable.Range(0, visual.Width * visual.Height)
            .Select(index => visual.Pixels[index * 4])
            .ToArray();
}
