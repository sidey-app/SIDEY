using Sidey.Core.Domain;

namespace Sidey.Core.Realtime;

public sealed record RealtimeRoomPlan(
    IReadOnlySet<Guid> Desired,
    IReadOnlySet<Guid> Additions,
    IReadOnlySet<Guid> Removals,
    Guid? ActiveRoomId)
{
    public static RealtimeRoomPlan Create(
        IReadOnlySet<Guid> existing,
        IEnumerable<Guid> requested,
        Guid? activeRoomId)
    {
        var desired = requested.Take(5).ToHashSet();
        return new RealtimeRoomPlan(
            desired,
            desired.Except(existing).ToHashSet(),
            existing.Except(desired).ToHashSet(),
            activeRoomId is { } candidate && desired.Contains(candidate) ? candidate : null);
    }
}

public sealed class RealtimeConnectionTracker
{
    private HashSet<Guid> _desiredRoomIds = [];
    private readonly HashSet<Guid> _subscribedRoomIds = [];

    public IReadOnlySet<Guid> DesiredRoomIds => _desiredRoomIds;
    public IReadOnlySet<Guid> SubscribedRoomIds => _subscribedRoomIds;
    public bool IsConnected => _subscribedRoomIds.SetEquals(_desiredRoomIds);

    public void ReplaceDesiredRoomIds(IEnumerable<Guid> roomIds)
    {
        _desiredRoomIds = roomIds.ToHashSet();
        _subscribedRoomIds.IntersectWith(_desiredRoomIds);
    }

    public void SetSubscribed(bool subscribed, Guid roomId)
    {
        if (!_desiredRoomIds.Contains(roomId) || !subscribed)
        {
            _subscribedRoomIds.Remove(roomId);
            return;
        }

        _subscribedRoomIds.Add(roomId);
    }
}

public static class PresencePublicationPlan
{
    public static PresenceState StateFor(
        Guid roomId,
        Guid? activeRoomId,
        PresenceState localPresence) =>
        roomId != activeRoomId
            ? PresenceState.Offline
            : localPresence == PresenceState.Away ? PresenceState.Away : PresenceState.Online;
}

public sealed record PresenceUpdate(Guid UserId, PresenceState State);

public static class PresenceChangePlan
{
    public static IReadOnlyList<PresenceUpdate> Updates(
        IReadOnlyDictionary<Guid, PresenceState> joined,
        IReadOnlySet<Guid> left) =>
        left.Except(joined.Keys)
            .Select(userId => new PresenceUpdate(userId, PresenceState.Offline))
            .Concat(joined.Select(pair => new PresenceUpdate(pair.Key, pair.Value)))
            .OrderBy(update => update.UserId.ToString("D"), StringComparer.Ordinal)
            .ToArray();
}

public abstract record TypingLeaseAction(Guid RoomId)
{
    public sealed record Start(Guid TargetRoomId) : TypingLeaseAction(TargetRoomId);
    public sealed record Stop(Guid TargetRoomId) : TypingLeaseAction(TargetRoomId);
}

public sealed class TypingLease
{
    public static readonly TimeSpan KeepaliveInterval = TimeSpan.FromSeconds(2);
    public static readonly TimeSpan RemoteExpiry = TimeSpan.FromSeconds(4);

    public Guid? RoomId { get; private set; }

    public IReadOnlyList<TypingLeaseAction> Update(bool active, Guid? requestedRoomId)
    {
        if (!active || requestedRoomId is null)
        {
            if (RoomId is not { } stoppedRoomId)
            {
                return [];
            }

            RoomId = null;
            return [new TypingLeaseAction.Stop(stoppedRoomId)];
        }

        if (RoomId == requestedRoomId)
        {
            return [];
        }

        var actions = new List<TypingLeaseAction>(2);
        if (RoomId is { } previousRoomId)
        {
            actions.Add(new TypingLeaseAction.Stop(previousRoomId));
        }

        RoomId = requestedRoomId;
        actions.Add(new TypingLeaseAction.Start(requestedRoomId.Value));
        return actions;
    }
}

public sealed class CharacterPulseCooldown
{
    public static readonly TimeSpan Duration = TimeSpan.FromSeconds(10);

    private readonly Dictionary<(Guid RoomId, Guid UserId), TimeSpan> _lastAcceptedUptime = [];

    public bool Accept(Guid roomId, Guid userId, TimeSpan uptime)
    {
        if (uptime < TimeSpan.Zero)
        {
            return false;
        }

        var key = (roomId, userId);
        if (_lastAcceptedUptime.TryGetValue(key, out var last) && uptime - last < Duration)
        {
            return false;
        }

        _lastAcceptedUptime[key] = uptime;
        return true;
    }
}
