using Sidey.Core.Domain;
using Sidey.Overlay;

namespace Sidey.Platform.Windows.Tests;

public sealed class BubbleDecorationRenderingTests
{
    [Fact]
    public void StyledBubbleDecorationOccupiesOverflowInsteadOfCoveringTheBody()
    {
        string assetRoot = Path.Combine(AppContext.BaseDirectory, "Assets", "Bubbles");
        var memberId = Guid.NewGuid();
        var messageId = Guid.NewGuid();
        using var cache = new PixelTextVisualCache(
            dpi: 144,
            edge: OverlayEdge.Bottom,
            bubbleAssetRoot: assetRoot);
        cache.Update(new WorldSnapshot(
            RoomId: Guid.NewGuid(),
            Members:
            [
                new PixelWorldMember(
                    memberId,
                    "두부",
                    "pixel_cat",
                    PresenceState.Online,
                    IsTyping: false,
                    IsCurrentUser: false,
                    EquippedBubbleStyleId: "bubble_starry_cat"),
            ],
            Bubbles:
            [
                new ActiveBubble(
                    memberId,
                    messageId,
                    "5a",
                    DateTimeOffset.UtcNow.AddSeconds(8),
                    "bubble_starry_cat"),
            ],
            Pulses: [],
            Throws: [],
            Edge: OverlayEdge.Bottom,
            InstallationSeed: 51));

        PremultipliedVisual visual = cache.Get(memberId).MessageBubbles[messageId];
        PixelVisualBodyBounds body = Assert.IsType<PixelVisualBodyBounds>(visual.BubbleBodyBounds);

        Assert.True(body.X > 0);
        Assert.True(body.Y > 0);
        Assert.Equal(body.Width + body.X, visual.Width);
        Assert.Equal(body.Height + body.Y, visual.Height);
        Assert.True(CountVisibleOverflowPixels(visual, body) > 0);
    }

    private static int CountVisibleOverflowPixels(
        PremultipliedVisual visual,
        PixelVisualBodyBounds body)
    {
        int count = 0;
        for (int y = 0; y < visual.Height; y++)
        {
            for (int x = 0; x < visual.Width; x++)
            {
                if (x >= body.X && y >= body.Y)
                {
                    continue;
                }

                if (visual.Pixels[((y * visual.Width) + x) * 4 + 3] > 0)
                {
                    count++;
                }
            }
        }
        return count;
    }
}
