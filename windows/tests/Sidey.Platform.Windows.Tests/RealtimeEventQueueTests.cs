using Sidey.Core.Abstractions;
using Sidey.Infrastructure;

namespace Sidey.Platform.Windows.Tests;

public sealed class RealtimeEventQueueTests
{
    [Fact]
    public async Task OverflowDiscardsStaleEventsAndRequestsReconciliation()
    {
        var queue = new RealtimeEventQueue();
        int attempted = RealtimeEventQueue.Capacity + 44;
        for (int index = 0; index < attempted; index++)
        {
            queue.TryWrite(new BackendEvent.Diagnostic($"event-{index}"));
        }

        await using IAsyncEnumerator<BackendEvent> events = queue
            .ReadAllAsync(CancellationToken.None)
            .GetAsyncEnumerator();

        Assert.True(await events.MoveNextAsync());
        BackendEvent.Diagnostic overflow = Assert.IsType<BackendEvent.Diagnostic>(events.Current);
        Assert.Equal(
            $"realtime-event-queue-overflow capacity={RealtimeEventQueue.Capacity} dropped={attempted}",
            overflow.Stage);
        Assert.True(await events.MoveNextAsync());
        Assert.IsType<BackendEvent.ReconciliationRequired>(events.Current);

        Assert.True(queue.TryWrite(new BackendEvent.Diagnostic("after-reconciliation")));
        Assert.True(await events.MoveNextAsync());
        BackendEvent.Diagnostic recovered = Assert.IsType<BackendEvent.Diagnostic>(events.Current);
        Assert.Equal("after-reconciliation", recovered.Stage);
    }
}
