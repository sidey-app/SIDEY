namespace Sidey.Core.Realtime;

public enum RealtimeTopicKind
{
    Database,
    Ephemeral,
}

public readonly record struct RealtimeRoomDescriptor(
    Guid RoomId,
    long Epoch,
    RealtimeTopicKind Kind)
{
    public string ServerTopic =>
        $"room:{RoomId:D}:{Epoch}:{(Kind == RealtimeTopicKind.Database ? "db" : "ephemeral")}";

    public string PhoenixTopic => $"realtime:{ServerTopic}";

    public static bool TryParsePhoenixTopic(
        string? topic,
        out RealtimeRoomDescriptor descriptor)
    {
        descriptor = default;
        if (string.IsNullOrWhiteSpace(topic))
        {
            return false;
        }

        var parts = topic.Split(':', StringSplitOptions.None);
        if (parts.Length != 5
            || parts[0] != "realtime"
            || parts[1] != "room"
            || !Guid.TryParse(parts[2], out var roomId)
            || !long.TryParse(parts[3], out var epoch)
            || epoch < 1)
        {
            return false;
        }

        var kind = parts[4] switch
        {
            "db" => RealtimeTopicKind.Database,
            "ephemeral" => RealtimeTopicKind.Ephemeral,
            _ => (RealtimeTopicKind?)null,
        };
        if (kind is null)
        {
            return false;
        }

        descriptor = new RealtimeRoomDescriptor(roomId, epoch, kind.Value);
        return true;
    }
}

public sealed record RealtimeRoomSubscriptionDelta(
    IReadOnlyList<RealtimeRoomDescriptor> Leaves,
    IReadOnlyList<RealtimeRoomDescriptor> Joins);

public static class RealtimeEpochSubscriptionPlan
{
    public static RealtimeRoomSubscriptionDelta CreateDelta(
        IReadOnlyDictionary<Guid, long> current,
        IReadOnlyDictionary<Guid, long> desired)
    {
        ArgumentNullException.ThrowIfNull(current);
        ArgumentNullException.ThrowIfNull(desired);
        Validate(desired);

        var leaves = current
            .Where(pair => !desired.TryGetValue(pair.Key, out var epoch) || epoch != pair.Value)
            .OrderBy(pair => pair.Key)
            .SelectMany(pair => Descriptors(pair.Key, pair.Value))
            .ToArray();
        var joins = desired
            .Where(pair => !current.TryGetValue(pair.Key, out var epoch) || epoch != pair.Value)
            .OrderBy(pair => pair.Key)
            .SelectMany(pair => Descriptors(pair.Key, pair.Value))
            .ToArray();
        return new RealtimeRoomSubscriptionDelta(leaves, joins);
    }

    public static IEnumerable<RealtimeRoomDescriptor> Descriptors(Guid roomId, long epoch)
    {
        if (roomId == Guid.Empty)
        {
            throw new ArgumentException("Room ID cannot be empty.", nameof(roomId));
        }
        if (epoch < 1)
        {
            throw new ArgumentOutOfRangeException(nameof(epoch));
        }

        yield return new RealtimeRoomDescriptor(roomId, epoch, RealtimeTopicKind.Database);
        yield return new RealtimeRoomDescriptor(roomId, epoch, RealtimeTopicKind.Ephemeral);
    }

    private static void Validate(IReadOnlyDictionary<Guid, long> rooms)
    {
        if (rooms.Count > 5)
        {
            throw new ArgumentOutOfRangeException(nameof(rooms), "A user can subscribe to at most five rooms.");
        }
        if (rooms.Any(pair => pair.Key == Guid.Empty || pair.Value < 1))
        {
            throw new ArgumentException("Realtime rooms require a non-empty ID and a positive epoch.", nameof(rooms));
        }
    }
}
