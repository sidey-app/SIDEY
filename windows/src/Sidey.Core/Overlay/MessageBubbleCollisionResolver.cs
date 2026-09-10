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
        MessageBubbleCollisionScratch scratch,
        IReadOnlySet<Guid>? stoppedIds = null,
        double coordinateScale = 1d)
    {
        ArgumentNullException.ThrowIfNull(scratch);
        Dictionary<Guid, PixelMovementAgent> agentById = scratch.AgentById;
        Dictionary<Guid, double> acceleration = scratch.Acceleration;
        HashSet<Guid> separated = scratch.Separated;
        agentById.Clear();
        acceleration.Clear();
        separated.Clear();
        scratch.Transfers.Clear();
        scratch.TransferAcceleration.Clear();
        double deltaTime = Math.Clamp(rawDeltaTime, 0d, 0.1d);
        if (deltaTime <= 0d || messageBubbles.Count < 2)
        {
            for (int index = 0; index < agents.Count; index++)
                agents[index].MessageBubbleSeparationOrder = null;
            return separated;
        }

        for (int agentIndex = 0; agentIndex < agents.Count; agentIndex++)
        {
            PixelMovementAgent agent = agents[agentIndex];
            agentById[agent.Id] = agent;
        }
        for (int leftIndex = 0; leftIndex < messageBubbles.Count; leftIndex++)
        {
            for (int rightIndex = leftIndex + 1; rightIndex < messageBubbles.Count; rightIndex++)
            {
                MessageBubbleTrackBounds left = messageBubbles[leftIndex];
                MessageBubbleTrackBounds right = messageBubbles[rightIndex];
                double overlap = Math.Min(left.Upper, right.Upper)
                    - Math.Max(left.Lower, right.Lower)
                    + (RequiredGap * coordinateScale);
                if (overlap <= 0d
                    || !agentById.TryGetValue(left.MemberId, out PixelMovementAgent? leftAgent)
                    || !agentById.TryGetValue(right.MemberId, out PixelMovementAgent? rightAgent))
                {
                    continue;
                }

                leftAgent.MessageBubbleSeparationOrder ??= leftAgent.TrackPosition;
                rightAgent.MessageBubbleSeparationOrder ??= rightAgent.TrackPosition;
                double direction = leftAgent.MessageBubbleSeparationOrder < rightAgent.MessageBubbleSeparationOrder
                    || (leftAgent.MessageBubbleSeparationOrder == rightAgent.MessageBubbleSeparationOrder
                        && left.MemberId.CompareTo(right.MemberId) < 0)
                    ? -1d
                    : 1d;
                double force = direction * SeparationAcceleration * coordinateScale;
                Add(acceleration, left.MemberId, force);
                Add(acceleration, right.MemberId, -force);
                bool leftCanMove = CanMove(leftAgent, direction, geometry, stoppedIds);
                bool rightCanMove = CanMove(rightAgent, -direction, geometry, stoppedIds);
                if (leftCanMove && !rightCanMove)
                    scratch.Transfers.Add((left.MemberId, force));
                else if (!leftCanMove && rightCanMove)
                    scratch.Transfers.Add((right.MemberId, -force));
                separated.Add(left.MemberId);
                separated.Add(right.MemberId);
            }
        }

        for (int index = 0; index < agents.Count; index++)
        {
            PixelMovementAgent agent = agents[index];
            if (!separated.Contains(agent.Id))
                agent.MessageBubbleSeparationOrder = null;
        }
        foreach ((Guid Id, double Force) transfer in scratch.Transfers)
        {
            if (acceleration.GetValueOrDefault(transfer.Id) * transfer.Force > 0)
                Add(scratch.TransferAcceleration, transfer.Id, transfer.Force);
        }
        foreach (KeyValuePair<Guid, double> transfer in scratch.TransferAcceleration)
            Add(acceleration, transfer.Key, transfer.Value);
        foreach ((Guid id, double requestedForce) in acceleration)
        {
            PixelMovementAgent agent = agentById[id];
            if (stoppedIds?.Contains(id) == true)
            {
                agent.Velocity = 0;
                continue;
            }
            agent.IdleRemaining = 0d;
            double force = CanMove(agent, requestedForce, geometry, stoppedIds) ? requestedForce : 0d;
            if (Math.Abs(force) <= 0.001d)
            {
                agent.Velocity = 0;
                continue;
            }
            agent.Velocity = Math.Clamp(
                agent.Velocity + (force * deltaTime),
                -MaximumSeparationSpeed * coordinateScale,
                MaximumSeparationSpeed * coordinateScale);
            agent.TrackPosition = geometry.Clamp(agent.TrackPosition + (agent.Velocity * deltaTime));
        }

        return separated;
    }

    private static void Add(Dictionary<Guid, double> values, Guid id, double value) =>
        values[id] = values.GetValueOrDefault(id) + value;

    private static bool CanMove(PixelMovementAgent agent, double direction,
        EdgeTrackGeometry geometry, IReadOnlySet<Guid>? stoppedIds) =>
        stoppedIds?.Contains(agent.Id) != true && (direction < 0
            ? agent.TrackPosition > geometry.TrackLowerBound + 0.001d
            : agent.TrackPosition < geometry.TrackUpperBound - 0.001d);
}

public sealed class MessageBubbleCollisionScratch
{
    internal Dictionary<Guid, PixelMovementAgent> AgentById { get; } = [];
    internal Dictionary<Guid, double> Acceleration { get; } = [];
    internal HashSet<Guid> Separated { get; } = [];
    internal List<(Guid Id, double Force)> Transfers { get; } = [];
    internal Dictionary<Guid, double> TransferAcceleration { get; } = [];
}
