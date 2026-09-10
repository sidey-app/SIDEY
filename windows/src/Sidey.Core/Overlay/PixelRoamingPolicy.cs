namespace Sidey.Core.Overlay;

public static class PixelRoamingPolicy
{
    // Run after movement, like PixelWorldScene on macOS. Stopped members retain
    // their destination; overlap handling in the simulation may interrupt a rest.
    public static void UpdateAfterMovement(
        IList<PixelMovementAgent> agents, IReadOnlySet<Guid> stoppedIds,
        EdgeTrackGeometry geometry, Random random, double coordinateScale = 1d)
    {
        for (int index = 0; index < agents.Count; index++)
        {
            PixelMovementAgent agent = agents[index];
            if (stoppedIds.Contains(agent.Id)
                || Math.Abs(agent.TrackPosition - agent.Target) >= 3d * coordinateScale)
            {
                continue;
            }
            agent.IdleRemaining = 0.8d + (random.NextDouble() * 2.2d);
            agent.Target = geometry.TrackLowerBound
                + (random.NextDouble() * (geometry.TrackUpperBound - geometry.TrackLowerBound));
        }
    }

    public static bool IsWalking(PixelMovementAgent agent, bool stopped, double coordinateScale = 1d) =>
        !stopped && agent.IdleRemaining <= 0d && Math.Abs(agent.Velocity) > 2d * coordinateScale;
}
