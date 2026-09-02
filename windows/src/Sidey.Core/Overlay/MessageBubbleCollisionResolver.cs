namespace Sidey.Core.Overlay;

public sealed record MessageBubbleTrackBounds(Guid MemberId, double Lower, double Upper)
{
    public double Midpoint => (Lower + Upper) / 2d;
}

public static class MessageBubbleCollisionResolver
{
    public const double RequiredGap = 8d;
    public const double SeparationAcceleration = 240d;
    public const double MaximumSeparationSpeed = 72d;

    /// <summary>
    /// Applies pairwise tangent acceleration for real message bubbles. Typing
    /// bubbles are intentionally excluded by the caller. Pair order is stable
    /// so crowded tracks remain deterministic.
    /// </summary>
    public static IReadOnlySet<Guid> Apply(
        IList<PixelMovementAgent> agents,
        IReadOnlyList<MessageBubbleTrackBounds> messageBubbles,
        double rawDeltaTime,
        EdgeTrackGeometry geometry) =>
        Apply(
            agents,
            messageBubbles,
            rawDeltaTime,
            geometry,
            new MessageBubbleCollisionScratch());

    public static IReadOnlySet<Guid> Apply(
        IList<PixelMovementAgent> agents,
        IReadOnlyList<MessageBubbleTrackBounds> messageBubbles,
        double rawDeltaTime,
        EdgeTrackGeometry geometry,
        MessageBubbleCollisionScratch scratch)
    {
        ArgumentNullException.ThrowIfNull(scratch);
        var agentById = scratch.AgentById;
        var acceleration = scratch.Acceleration;
        var separated = scratch.Separated;
        agentById.Clear();
        acceleration.Clear();
        separated.Clear();
        var deltaTime = Math.Clamp(rawDeltaTime, 0d, 0.1d);
        if (deltaTime <= 0d || messageBubbles.Count < 2)
        {
            return separated;
        }

        for (var agentIndex = 0; agentIndex < agents.Count; agentIndex++)
        {
            var agent = agents[agentIndex];
            agentById[agent.Id] = agent;
        }
        for (var leftIndex = 0; leftIndex < messageBubbles.Count; leftIndex++)
        {
            for (var rightIndex = leftIndex + 1; rightIndex < messageBubbles.Count; rightIndex++)
            {
                var left = messageBubbles[leftIndex];
                var right = messageBubbles[rightIndex];
                var overlap = Math.Min(left.Upper, right.Upper)
                    - Math.Max(left.Lower, right.Lower)
                    + RequiredGap;
                if (overlap <= 0d
                    || !agentById.TryGetValue(left.MemberId, out var leftAgent)
                    || !agentById.TryGetValue(right.MemberId, out var rightAgent))
                {
                    continue;
                }

                var direction = left.Midpoint < right.Midpoint
                    || (left.Midpoint == right.Midpoint
                        && left.MemberId.CompareTo(right.MemberId) < 0)
                    ? -1d
                    : 1d;
                Add(acceleration, left.MemberId, direction * SeparationAcceleration);
                Add(acceleration, right.MemberId, -direction * SeparationAcceleration);
                leftAgent.IdleRemaining = 0d;
                rightAgent.IdleRemaining = 0d;
                separated.Add(left.MemberId);
                separated.Add(right.MemberId);
            }
        }

        foreach (var (id, force) in acceleration)
        {
            var agent = agentById[id];
            agent.Velocity = Math.Clamp(
                agent.Velocity + (force * deltaTime),
                -MaximumSeparationSpeed,
                MaximumSeparationSpeed);
            agent.TrackPosition = geometry.Clamp(agent.TrackPosition + (agent.Velocity * deltaTime));
        }

        return separated;
    }

    private static void Add(Dictionary<Guid, double> values, Guid id, double value) =>
        values[id] = values.GetValueOrDefault(id) + value;
}

public sealed class MessageBubbleCollisionScratch
{
    internal Dictionary<Guid, PixelMovementAgent> AgentById { get; } = [];
    internal Dictionary<Guid, double> Acceleration { get; } = [];
    internal HashSet<Guid> Separated { get; } = [];
}
