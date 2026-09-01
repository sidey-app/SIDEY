using Sidey.Core.Overlay;

namespace Sidey.Core.Tests;

public sealed class MessageBubbleCollisionTests
{
    [Fact]
    public void RealMessageBubblesEndIdleAndSeparateAtTheDocumentedLimit()
    {
        var leftId = Guid.Parse("00000000-0000-0000-0000-000000000001");
        var rightId = Guid.Parse("00000000-0000-0000-0000-000000000002");
        var geometry = new EdgeTrackGeometry(new RectD(0, 0, 500, 240), Sidey.Core.Domain.OverlayEdge.Bottom);
        var agents = new List<PixelMovementAgent>
        {
            new(leftId, 220, 400, idleRemaining: 10),
            new(rightId, 240, 40, idleRemaining: 10),
        };

        var affected = MessageBubbleCollisionResolver.Apply(
            agents,
            [
                new MessageBubbleTrackBounds(leftId, 180, 260),
                new MessageBubbleTrackBounds(rightId, 220, 300),
            ],
            1d / 30d,
            geometry);

        Assert.Equal(2, affected.Count);
        Assert.Equal(0, agents[0].IdleRemaining);
        Assert.Equal(0, agents[1].IdleRemaining);
        Assert.True(agents[0].Velocity < 0);
        Assert.True(agents[1].Velocity > 0);
        Assert.All(agents, agent => Assert.InRange(
            Math.Abs(agent.Velocity),
            0,
            MessageBubbleCollisionResolver.MaximumSeparationSpeed));
    }
}
