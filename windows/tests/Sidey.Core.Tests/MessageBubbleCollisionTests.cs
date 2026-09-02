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

    [Fact]
    public void ReusableScratchAvoidsPerFrameCollisionAllocations()
    {
        var firstId = Guid.NewGuid();
        var secondId = Guid.NewGuid();
        var geometry = new EdgeTrackGeometry(
            new RectD(0, 0, 500, 240),
            Sidey.Core.Domain.OverlayEdge.Bottom);
        var agents = new List<PixelMovementAgent>
        {
            new(firstId, 220, 400),
            new(secondId, 240, 40),
        };
        var bubbles = new List<MessageBubbleTrackBounds>
        {
            new(firstId, 180, 260),
            new(secondId, 220, 300),
        };
        var scratch = new MessageBubbleCollisionScratch();

        for (var index = 0; index < 100; index++)
        {
            MessageBubbleCollisionResolver.Apply(
                agents, bubbles, 1d / 30d, geometry, scratch);
        }

        var before = GC.GetAllocatedBytesForCurrentThread();
        for (var index = 0; index < 1_000; index++)
        {
            MessageBubbleCollisionResolver.Apply(
                agents, bubbles, 1d / 30d, geometry, scratch);
        }
        var allocated = GC.GetAllocatedBytesForCurrentThread() - before;

        Assert.InRange(allocated, 0, 4_096);
    }
}
