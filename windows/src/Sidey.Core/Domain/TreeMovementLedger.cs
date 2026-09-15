namespace Sidey.Core.Domain;

/// <summary>Keeps account profile state monotonic across room snapshots and RPC replies.</summary>
public sealed class TreeMovementLedger
{
    private readonly Dictionary<Guid, (bool Paused, long Revision)> _confirmed = [];

    public (bool Paused, long? Revision) Merge(Guid userId, bool paused, long? revision)
    {
        if (_confirmed.TryGetValue(userId, out (bool Paused, long Revision) current)
            && (revision is null || revision <= current.Revision))
            return (current.Paused, current.Revision);
        if (revision is >= 0)
            _confirmed[userId] = (paused, revision.Value);
        return (paused, revision);
    }

    public void Clear() => _confirmed.Clear();
}
