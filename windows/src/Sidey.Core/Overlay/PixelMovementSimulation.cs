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
    public double? MessageBubbleSeparationOrder { get; set; }
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
        IReadOnlySet<Guid> stoppedIds) =>
        Step(
            agents,
            rawDeltaTime,
            geometry,
            avoidanceRects,
            stoppedIds,
            new PixelMovementScratch());

    public static void Step(
        IList<PixelMovementAgent> agents,
        double rawDeltaTime,
        EdgeTrackGeometry geometry,
        IReadOnlyList<RectD> avoidanceRects,
        IReadOnlySet<Guid> stoppedIds,
        PixelMovementScratch scratch,
        double coordinateScale = 1d,
        IReadOnlySet<Guid>? alreadyMovedIds = null)
    {
        ArgumentNullException.ThrowIfNull(scratch);
        if (!double.IsFinite(coordinateScale) || coordinateScale <= 0d)
            throw new ArgumentOutOfRangeException(nameof(coordinateScale));
        if (agents.Count == 0 || !double.IsFinite(geometry.TangentLength))
        {
            return;
        }

        double deltaTime = Math.Clamp(rawDeltaTime, 0d, 0.1d);
        if (deltaTime <= 0d)
        {
            return;
        }

        Dictionary<Guid, double> separation = scratch.Separation;
        HashSet<Guid> overlappingIds = scratch.OverlappingIds;
        separation.Clear();
        overlappingIds.Clear();
        for (int leftIndex = 0; leftIndex < agents.Count; leftIndex++)
        {
            for (int rightIndex = leftIndex + 1; rightIndex < agents.Count; rightIndex++)
            {
                PixelMovementAgent left = agents[leftIndex];
                PixelMovementAgent right = agents[rightIndex];
                double delta = left.TrackPosition - right.TrackPosition;
                double distance = Math.Abs(delta);
                double desiredDistance = CharacterRadius * 2d * coordinateScale;
                if (distance >= desiredDistance)
                {
                    continue;
                }

                double direction = distance > 0.001d
                    ? delta < 0d ? -1d : 1d
                    : left.Id.CompareTo(right.Id) < 0 ? -1d : 1d;
                double strength = Math.Max(0d, 1d - (distance / desiredDistance)) * 30d * coordinateScale;
                separation[left.Id] = separation.GetValueOrDefault(left.Id) + (direction * strength);
                separation[right.Id] = separation.GetValueOrDefault(right.Id) - (direction * strength);
                overlappingIds.Add(left.Id);
                overlappingIds.Add(right.Id);
            }
        }

        for (int agentIndex = 0; agentIndex < agents.Count; agentIndex++)
        {
            PixelMovementAgent agent = agents[agentIndex];
            if (alreadyMovedIds?.Contains(agent.Id) == true)
                continue;
            if (stoppedIds.Contains(agent.Id))
            {
                agent.Velocity = 0d;
                continue;
            }

            bool isOverlapping = overlappingIds.Contains(agent.Id);
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

            double delta = (agent.Target - agent.TrackPosition) / coordinateScale;
            double separationForce = separation.GetValueOrDefault(agent.Id);
            double targetDirection = Math.Abs(delta) > 2d
                ? delta < 0d ? -1d : 1d
                : Math.Abs(agent.Velocity) > 0.1d * coordinateScale
                    ? agent.Velocity < 0d ? -1d : 1d
                    : separationForce < 0d ? -1d : 1d;
            double acceleration = Math.Abs(delta) > 2d ? targetDirection * 32d * coordinateScale : 0d;

            if (isOverlapping)
            {
                acceleration += targetDirection * OverlapForwardAcceleration * coordinateScale;
                if (separationForce * targetDirection > 0d)
                {
                    acceleration += separationForce;
                }
            }
            else
            {
                acceleration += separationForce;
            }

            for (int rectIndex = 0; rectIndex < avoidanceRects.Count; rectIndex++)
            {
                acceleration += AvoidanceForce(
                    agent.TrackPosition,
                    geometry,
                    avoidanceRects[rectIndex], coordinateScale);
            }

            agent.Velocity += acceleration * deltaTime;
            double damping = isOverlapping ? 0.92d : 0.82d;
            agent.Velocity *= Math.Pow(damping, deltaTime * 30d);
            double speedLimit = isOverlapping ? OverlapMaximumSpeed : MaximumSpeed;
            agent.Velocity = Math.Clamp(agent.Velocity, -speedLimit * coordinateScale, speedLimit * coordinateScale);
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
        RectD rect, double coordinateScale)
    {
        RectD expanded = rect.Inset(-CharacterRadius * coordinateScale, -CharacterRadius * coordinateScale);
        PointD point = geometry.PointFor(trackPosition);
        if (!expanded.Contains(point))
        {
            return 0d;
        }

        double lower = geometry.Edge is OverlayEdge.Bottom or OverlayEdge.Top
            ? expanded.MinX - geometry.Bounds.MinX
            : expanded.MinY - geometry.Bounds.MinY;
        double upper = geometry.Edge is OverlayEdge.Bottom or OverlayEdge.Top
            ? expanded.MaxX - geometry.Bounds.MinX
            : expanded.MaxY - geometry.Bounds.MinY;
        return (trackPosition - lower < upper - trackPosition ? -90d : 90d) * coordinateScale;
    }
}

public sealed class PixelMovementScratch
{
    internal Dictionary<Guid, double> Separation { get; } = [];
    internal HashSet<Guid> OverlappingIds { get; } = [];
}
