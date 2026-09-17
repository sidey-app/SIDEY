using System.Runtime.CompilerServices;
using System.Threading.Channels;
using Sidey.Core.Abstractions;

namespace Sidey.Infrastructure.Realtime;

internal sealed class RealtimeEventQueue
{
    internal const int Capacity = 256;

    private readonly Channel<BackendEvent> _events = Channel.CreateBounded<BackendEvent>(
        new BoundedChannelOptions(Capacity)
        {
            FullMode = BoundedChannelFullMode.Wait,
            SingleReader = true,
            SingleWriter = false,
        });
    private readonly object _controlLock = new();
    private readonly Dictionary<Guid, BackendEvent.RoomRevoked> _revocations = [];
    private long? _invalidatedRevision;
    private int _overflowed;
    private long _overflowCount;

    internal int Count => _events.Reader.Count;

    internal bool TryWrite(BackendEvent backendEvent)
    {
        bool retainedControl = backendEvent is BackendEvent.RoomRevoked;
        if (backendEvent is BackendEvent.RoomRevoked revoked)
        {
            lock (_controlLock)
            {
                if (_invalidatedRevision is { } invalidated)
                    _invalidatedRevision = Math.Max(invalidated, revoked.MembershipRevision);
                else if (_revocations.Count == Capacity && !_revocations.ContainsKey(revoked.RoomId))
                {
                    // A stalled consumer must never retain private room data. Coalesce
                    // an extreme control backlog into one bounded local access reset.
                    _invalidatedRevision = Math.Max(revoked.MembershipRevision,
                        _revocations.Values.Max(value => value.MembershipRevision));
                    _revocations.Clear();
                }
                else if (!_revocations.TryGetValue(revoked.RoomId, out BackendEvent.RoomRevoked? old)
                    || old.MembershipRevision < revoked.MembershipRevision)
                    _revocations[revoked.RoomId] = revoked;
            }
        }
        if (_events.Writer.TryWrite(backendEvent))
        {
            return true;
        }

        Interlocked.Exchange(ref _overflowed, 1);
        Interlocked.Increment(ref _overflowCount);
        return retainedControl;
    }

    internal async IAsyncEnumerable<BackendEvent> ReadAllAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        while (await _events.Reader.WaitToReadAsync(cancellationToken).ConfigureAwait(false))
        {
            while (_events.Reader.TryRead(out BackendEvent? backendEvent))
            {
                foreach (BackendEvent control in TakeControls())
                    yield return control;
                if (Interlocked.Exchange(ref _overflowed, 0) != 0)
                {
                    long dropped = 1 + Interlocked.Exchange(ref _overflowCount, 0);
                    while (_events.Reader.TryRead(out _))
                    {
                        dropped++;
                    }

                    foreach (BackendEvent control in TakeControls())
                        yield return control;
                    yield return new BackendEvent.Diagnostic(
                        $"realtime-event-queue-overflow capacity={Capacity} dropped={dropped}");
                    yield return new BackendEvent.ReconciliationRequired();
                    break;
                }

                if (backendEvent is not BackendEvent.RoomRevoked)
                    yield return backendEvent;
            }
        }
    }

    private BackendEvent[] TakeControls()
    {
        lock (_controlLock)
        {
            BackendEvent[] controls = _invalidatedRevision is { } revision
                ? [new BackendEvent.RoomAccessInvalidated(revision)]
                : [.. _revocations.Values.OrderBy(value => value.MembershipRevision)];
            _revocations.Clear();
            _invalidatedRevision = null;
            return controls;
        }
    }

    internal void Complete() => _events.Writer.TryComplete();
}
