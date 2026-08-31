using Sidey.Core.Domain;
using Sidey.Core.Overlay;

namespace Sidey.Core.Tests;

public sealed class PixelMovementSimulationTests
{
    [Fact]
    public void TwentyAgentsStayFiniteAndInsideEveryEdgeForThreeThousandTicks()
    {
        foreach (var edge in Enum.GetValues<OverlayEdge>())
        {
            var bounds = edge is OverlayEdge.Bottom or OverlayEdge.Top
                ? new RectD(0, 0, 1_200, 240)
                : new RectD(0, 0, 240, 1_200);
            var geometry = new EdgeTrackGeometry(bounds, edge);
            var agents = Enumerable.Range(0, 20)
                .Select(index => new PixelMovementAgent(
                    Guid.NewGuid(),
                    geometry.TrackLowerBound + (index * 10d),
                    geometry.TrackUpperBound - (index * 9d)))
                .ToList();
            IReadOnlyList<RectD> avoidance = edge == OverlayEdge.Bottom
                ? [new RectD(380, 0, 440, 76)]
                : [];

            for (var tick = 0; tick < 3_000; tick++)
            {
                PixelMovementSimulation.Step(
                    agents,
                    1d / 30d,
                    geometry,
                    avoidance,
                    new HashSet<Guid>());
            }

            foreach (var agent in agents)
            {
                Assert.True(double.IsFinite(agent.TrackPosition));
                Assert.True(double.IsFinite(agent.Velocity));
                Assert.InRange(agent.TrackPosition, geometry.TrackLowerBound, geometry.TrackUpperBound);
            }
        }
    }

    [Fact]
    public void CrowdedTrackAllowsSafeOverlapWithoutNonFiniteValues()
    {
        var geometry = new EdgeTrackGeometry(new RectD(0, 0, 48, 240), OverlayEdge.Bottom);
        var agents = Enumerable.Range(0, 20)
            .Select(_ => new PixelMovementAgent(Guid.NewGuid(), 24, 24))
            .ToList();

        for (var tick = 0; tick < 300; tick++)
        {
            PixelMovementSimulation.Step(agents, 1d / 30d, geometry, [geometry.Bounds], new HashSet<Guid>());
        }

        Assert.All(agents, agent =>
        {
            Assert.True(double.IsFinite(agent.TrackPosition));
            Assert.True(double.IsFinite(agent.Velocity));
        });
    }

    [Fact]
    public void OverlappingHeadOnAgentsAccelerateThrough()
    {
        var geometry = new EdgeTrackGeometry(new RectD(0, 0, 320, 240), OverlayEdge.Bottom);
        var agents = new List<PixelMovementAgent>
        {
            new(Guid.NewGuid(), 120, 280, velocity: 8),
            new(Guid.NewGuid(), 160, 40, velocity: -8),
        };

        PixelMovementSimulation.Step(agents, 1d / 30d, geometry, [], new HashSet<Guid>());

        Assert.True(agents[0].Velocity > 8);
        Assert.True(agents[1].Velocity < -8);
        Assert.True(agents[0].TrackPosition > 120);
        Assert.True(agents[1].TrackPosition < 160);
    }

    [Fact]
    public void OverlapEndsIdleAndStoppedPresenceDoesNotMove()
    {
        var stoppedId = Guid.NewGuid();
        var geometry = new EdgeTrackGeometry(new RectD(0, 0, 320, 240), OverlayEdge.Bottom);
        var agents = new List<PixelMovementAgent>
        {
            new(Guid.NewGuid(), 140, 280, idleRemaining: 1),
            new(Guid.NewGuid(), 145, 40, idleRemaining: 1),
            new(stoppedId, 220, 40, velocity: 8),
        };

        PixelMovementSimulation.Step(agents, 1d / 30d, geometry, [], new HashSet<Guid> { stoppedId });

        Assert.Equal(0d, agents[0].IdleRemaining);
        Assert.Equal(0d, agents[1].IdleRemaining);
        Assert.NotEqual(140d, agents[0].TrackPosition);
        Assert.NotEqual(145d, agents[1].TrackPosition);
        Assert.Equal(220d, agents[2].TrackPosition);
        Assert.Equal(0d, agents[2].Velocity);
    }
}
