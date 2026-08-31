using Sidey.Core.Domain;

namespace Sidey.Core.Overlay;

public sealed class PixelMovementAgent(
    Guid id,
    double trackPosition,
    double target,
    double velocity = 0d,
    double idleRemaining = 0d)
{
    public Guid Id { get; } = id;
    public double TrackPosition { get; set; } = trackPosition;
    public double Velocity { get; set; } = velocity;
    public double Target { get; set; } = target;
    public double IdleRemaining { get; set; } = idleRemaining;
}

public static class PixelMovementPolicy
{
    public static IReadOnlySet<Guid> StoppedMemberIds(IEnumerable<PixelWorldMember> members) =>
        members
            .Where(member => member.Presence is PresenceState.Away or PresenceState.Offline or PresenceState.Reconnecting)
            .Select(member => member.Id)
            .ToHashSet();
}

public static class PixelMovementSimulation
{
    public const double CharacterRadius = 25d;
    public const double MaximumSpeed = 22d;
    public const double OverlapMaximumSpeed = 30d;
    public const double OverlapForwardAcceleration = 64d;

    public static void Step(
        IList<PixelMovementAgent> agents,
        double rawDeltaTime,
        EdgeTrackGeometry geometry,
        IReadOnlyList<RectD> avoidanceRects,
        IReadOnlySet<Guid> stoppedIds)
    {
        if (agents.Count == 0 || !double.IsFinite(geometry.TangentLength))
        {
            return;
        }

        var deltaTime = Math.Clamp(rawDeltaTime, 0d, 0.1d);
        if (deltaTime <= 0d)
        {
            return;
        }

        var separation = new Dictionary<Guid, double>();
        var overlappingIds = new HashSet<Guid>();
        for (var leftIndex = 0; leftIndex < agents.Count; leftIndex++)
        {
            for (var rightIndex = leftIndex + 1; rightIndex < agents.Count; rightIndex++)
            {
                var left = agents[leftIndex];
                var right = agents[rightIndex];
                var delta = left.TrackPosition - right.TrackPosition;
                var distance = Math.Abs(delta);
                var desiredDistance = CharacterRadius * 2d;
                if (distance >= desiredDistance)
                {
                    continue;
                }

                var direction = distance > 0.001d
                    ? delta < 0d ? -1d : 1d
                    : StringComparer.Ordinal.Compare(left.Id.ToString("D"), right.Id.ToString("D")) < 0 ? -1d : 1d;
                var strength = Math.Max(0d, 1d - (distance / desiredDistance)) * 30d;
                separation[left.Id] = separation.GetValueOrDefault(left.Id) + (direction * strength);
                separation[right.Id] = separation.GetValueOrDefault(right.Id) - (direction * strength);
                overlappingIds.Add(left.Id);
                overlappingIds.Add(right.Id);
            }
        }

        foreach (var agent in agents)
        {
            if (stoppedIds.Contains(agent.Id))
            {
                agent.Velocity = 0d;
                continue;
            }

            var isOverlapping = overlappingIds.Contains(agent.Id);
            if (agent.IdleRemaining > 0d && !isOverlapping)
            {
                agent.IdleRemaining = Math.Max(0d, agent.IdleRemaining - deltaTime);
                agent.Velocity = 0d;
                continue;
            }

            if (isOverlapping)
            {
                agent.IdleRemaining = 0d;
            }

            var delta = agent.Target - agent.TrackPosition;
            var separationForce = separation.GetValueOrDefault(agent.Id);
            var targetDirection = Math.Abs(delta) > 2d
                ? delta < 0d ? -1d : 1d
                : Math.Abs(agent.Velocity) > 0.1d
                    ? agent.Velocity < 0d ? -1d : 1d
                    : separationForce < 0d ? -1d : 1d;
            var acceleration = Math.Abs(delta) > 2d ? targetDirection * 32d : 0d;

            if (isOverlapping)
            {
                acceleration += targetDirection * OverlapForwardAcceleration;
                if (separationForce * targetDirection > 0d)
                {
                    acceleration += separationForce;
                }
            }
            else
            {
                acceleration += separationForce;
            }

            foreach (var rect in avoidanceRects)
            {
                acceleration += AvoidanceForce(agent.TrackPosition, geometry, rect);
            }

            agent.Velocity += acceleration * deltaTime;
            var damping = isOverlapping ? 0.92d : 0.82d;
            agent.Velocity *= Math.Pow(damping, deltaTime * 30d);
            var speedLimit = isOverlapping ? OverlapMaximumSpeed : MaximumSpeed;
            agent.Velocity = Math.Clamp(agent.Velocity, -speedLimit, speedLimit);
            agent.TrackPosition = geometry.Clamp(agent.TrackPosition + (agent.Velocity * deltaTime));

            if (!double.IsFinite(agent.TrackPosition) || !double.IsFinite(agent.Velocity))
            {
                agent.TrackPosition = geometry.TrackLowerBound;
                agent.Velocity = 0d;
            }
        }
    }

    private static double AvoidanceForce(
        double trackPosition,
        EdgeTrackGeometry geometry,
        RectD rect)
    {
        var expanded = rect.Inset(-CharacterRadius, -CharacterRadius);
        var point = geometry.PointFor(trackPosition);
        if (!expanded.Contains(point))
        {
            return 0d;
        }

        var lower = geometry.Edge is OverlayEdge.Bottom or OverlayEdge.Top
            ? expanded.MinX - geometry.Bounds.MinX
            : expanded.MinY - geometry.Bounds.MinY;
        var upper = geometry.Edge is OverlayEdge.Bottom or OverlayEdge.Top
            ? expanded.MaxX - geometry.Bounds.MinX
            : expanded.MaxY - geometry.Bounds.MinY;
        return trackPosition - lower < upper - trackPosition ? -90d : 90d;
    }
}
