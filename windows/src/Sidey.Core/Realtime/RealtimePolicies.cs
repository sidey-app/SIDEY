using Sidey.Core.Domain;

namespace Sidey.Core.Realtime;

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
    public static readonly TimeSpan Duration = TimeSpan.FromSeconds(1);

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

public static class RealtimeRecoveryPolicy
{
    public static readonly TimeSpan WatchdogInterval = TimeSpan.FromSeconds(5);

    public static TimeSpan DelayForAttempt(int attempt) => attempt switch
    {
        <= 0 => TimeSpan.Zero,
        1 => TimeSpan.FromSeconds(8),
        2 => TimeSpan.FromSeconds(16),
        _ => TimeSpan.FromSeconds(30),
    };
}

/// <summary>
/// Serializes complete Presence batches and coalesces work that has not begun
/// yet. Intermediate callers complete with the latest full publication.
/// </summary>
public sealed class CoalescingPublicationQueue<T>(Func<T, CancellationToken, Task> publish)
    : IAsyncDisposable
{
    private readonly object _gate = new();
    private readonly Func<T, CancellationToken, Task> _publish = publish
        ?? throw new ArgumentNullException(nameof(publish));
    private readonly CancellationTokenSource _shutdown = new();
    private Pending? _latest;
    private Task? _worker;

    public Task SubmitAsync(T state, CancellationToken cancellationToken = default)
    {
        var completion = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        lock (_gate)
        {
            if (_latest is { } superseded)
            {
                superseded.Completions.Add(completion);
                _latest = new Pending(
                    state,
                    superseded.Completions,
                    cancellationToken);
            }
            else
            {
                _latest = new Pending(
                    state,
                    [completion],
                    cancellationToken);
            }
            _worker ??= Task.Run(DrainAsync, CancellationToken.None);
        }

        return completion.Task;
    }

    public async ValueTask DisposeAsync()
    {
        _shutdown.Cancel();
        Task? worker;
        lock (_gate)
        {
            if (_latest is { } latest)
            {
                Complete(latest.Completions, completion => completion.TrySetCanceled());
            }
            _latest = null;
            worker = _worker;
        }

        if (worker is not null)
        {
            try
            {
                await worker.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }
        }

        _shutdown.Dispose();
    }

    private async Task DrainAsync()
    {
        while (!_shutdown.IsCancellationRequested)
        {
            Pending? pending;
            lock (_gate)
            {
                pending = _latest;
                _latest = null;
                if (pending is null)
                {
                    _worker = null;
                    return;
                }
            }

            using var linked = CancellationTokenSource.CreateLinkedTokenSource(
                _shutdown.Token,
                pending.CancellationToken);
            try
            {
                await _publish(pending.State, linked.Token).ConfigureAwait(false);
                Complete(pending.Completions, completion => completion.TrySetResult());
            }
            catch (OperationCanceledException) when (linked.IsCancellationRequested)
            {
                Complete(
                    pending.Completions,
                    completion => completion.TrySetCanceled(linked.Token));
            }
            catch (Exception exception)
            {
                Complete(
                    pending.Completions,
                    completion => completion.TrySetException(exception));
            }
        }
    }

    private static void Complete(
        IEnumerable<TaskCompletionSource> completions,
        Action<TaskCompletionSource> complete)
    {
        foreach (var completion in completions)
        {
            complete(completion);
        }
    }

    private sealed record Pending(
        T State,
        List<TaskCompletionSource> Completions,
        CancellationToken CancellationToken);
}
