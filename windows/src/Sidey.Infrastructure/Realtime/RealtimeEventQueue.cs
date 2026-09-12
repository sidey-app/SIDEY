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
    private int _overflowed;
    private long _overflowCount;

    internal int Count => _events.Reader.Count;

    internal bool TryWrite(BackendEvent backendEvent)
    {
        if (_events.Writer.TryWrite(backendEvent))
        {
            return true;
        }

        Interlocked.Exchange(ref _overflowed, 1);
        Interlocked.Increment(ref _overflowCount);
        return false;
    }

    internal async IAsyncEnumerable<BackendEvent> ReadAllAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        while (await _events.Reader.WaitToReadAsync(cancellationToken).ConfigureAwait(false))
        {
            while (_events.Reader.TryRead(out BackendEvent? backendEvent))
            {
                if (Interlocked.Exchange(ref _overflowed, 0) != 0)
                {
                    long dropped = 1 + Interlocked.Exchange(ref _overflowCount, 0);
                    while (_events.Reader.TryRead(out _))
                    {
                        dropped++;
                    }

                    yield return new BackendEvent.Diagnostic(
                        $"realtime-event-queue-overflow capacity={Capacity} dropped={dropped}");
                    yield return new BackendEvent.ReconciliationRequired();
                    break;
                }

                yield return backendEvent;
            }
        }
    }

    internal void Complete() => _events.Writer.TryComplete();
}
