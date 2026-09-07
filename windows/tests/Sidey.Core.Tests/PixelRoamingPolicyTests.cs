using Sidey.Core.Domain;
using Sidey.Core.Overlay;

namespace Sidey.Core.Tests;

public sealed class PixelRoamingPolicyTests
{
    private static readonly HashSet<Guid> NoStops = [];

    [Theory]
    [InlineData(1d)]
    [InlineData(1.25d)]
    [InlineData(1.5d)]
    [InlineData(2d)]
    public void ArrivalRestAndWalkingMatchMacAtEveryScale(double scale)
    {
        var geometry = new EdgeTrackGeometry(new RectD(0, 0, 1000 * scale, 280 * scale), OverlayEdge.Bottom);
        var agent = new PixelMovementAgent(Guid.NewGuid(), 100 * scale, 102.9 * scale, 4 * scale);
        PixelRoamingPolicy.UpdateAfterMovement([agent], NoStops, geometry, new Random(42), scale);
        Assert.InRange(agent.IdleRemaining, 0.8, 3);
        Assert.InRange(agent.Target, geometry.TrackLowerBound, geometry.TrackUpperBound);
        Assert.False(PixelRoamingPolicy.IsWalking(agent, false, scale));
        double position = agent.TrackPosition;
        double target = agent.Target;
        PixelMovementSimulation.Step([agent], 1d / 30, geometry, [], NoStops, new(), scale);
        Assert.Equal(position, agent.TrackPosition);
        Assert.Equal(target, agent.Target);
        Assert.Equal(0, agent.Velocity);
        agent.IdleRemaining = 0;
        agent.Velocity = 2 * scale;
        Assert.False(PixelRoamingPolicy.IsWalking(agent, false, scale));
        agent.Velocity = 2.01 * scale;
        Assert.True(PixelRoamingPolicy.IsWalking(agent, false, scale));
        Assert.False(PixelRoamingPolicy.IsWalking(agent, true, scale));
    }

    [Fact]
    public void ThreePointBoundaryAndStoppedMembersDoNotRetarget()
    {
        var geometry = new EdgeTrackGeometry(new RectD(0, 0, 1000, 280), OverlayEdge.Bottom);
        var agent = new PixelMovementAgent(Guid.NewGuid(), 100, 103);
        PixelRoamingPolicy.UpdateAfterMovement([agent], NoStops, geometry, new Random(42));
        Assert.Equal(103, agent.Target);
        agent.Target = 101;
        PixelRoamingPolicy.UpdateAfterMovement([agent], new HashSet<Guid> { agent.Id }, geometry, new Random(42));
        Assert.Equal(101, agent.Target);
        Assert.Equal(0, agent.IdleRemaining);
    }

    [Theory]
    [InlineData(1.25d)]
    [InlineData(1.5d)]
    [InlineData(2d)]
    public void DisplayScaleDoesNotChangeLogicalSpeed(double scale)
    {
        var normal = new PixelMovementAgent(Guid.NewGuid(), 100, 800);
        var scaled = new PixelMovementAgent(normal.Id, 100 * scale, 800 * scale);
        var normalGeometry = new EdgeTrackGeometry(new RectD(0, 0, 1000, 280), OverlayEdge.Bottom);
        var scaledGeometry = new EdgeTrackGeometry(new RectD(0, 0, 1000 * scale, 280 * scale), OverlayEdge.Bottom);
        for (int tick = 0; tick < 300; tick++)
        {
            PixelMovementSimulation.Step([normal], 1d / 30, normalGeometry, [], NoStops, new());
            PixelMovementSimulation.Step([scaled], 1d / 30, scaledGeometry, [], NoStops, new(), scale);
        }
        Assert.Equal(normal.TrackPosition, scaled.TrackPosition / scale, 8);
        Assert.Equal(normal.Velocity, scaled.Velocity / scale, 8);
    }

    [Fact]
    public void BubbleSeparationKeepsHitTargetStillAndDoesNotRunNormalMovementTwice()
    {
        var geometry = new EdgeTrackGeometry(new RectD(0, 0, 1000, 280), OverlayEdge.Bottom);
        var left = new PixelMovementAgent(Guid.NewGuid(), 200, 800, idleRemaining: 2);
        var right = new PixelMovementAgent(Guid.NewGuid(), 250, 100, idleRemaining: 2);
        var stopped = new HashSet<Guid> { right.Id };
        PixelMovementAgent[] agents = [left, right];
        var separated = MessageBubbleCollisionResolver.Apply(agents,
            [new(left.Id, 150, 280), new(right.Id, 220, 350)], 1d / 30, geometry, new(), stopped);
        Assert.Equal(250, right.TrackPosition);
        Assert.Equal(100, right.Target);
        Assert.Equal(2, right.IdleRemaining);
        Assert.Equal(-16, left.Velocity, 8);
        double movedPosition = left.TrackPosition;
        PixelMovementSimulation.Step(agents, 1d / 30, geometry, [], stopped, new(), 1, separated);
        Assert.Equal(movedPosition, left.TrackPosition);
    }
}
