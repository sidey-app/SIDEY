using Sidey.Core.Abstractions;
using Sidey.Infrastructure.Realtime;

namespace Sidey.Platform.Windows.Tests;

public sealed class RealtimeEventQueueTests
{
    [Fact]
    public async Task LaterOverflowWaveStillDeliversRevocationBeforeRecoveryCompletes()
    {
        var queue = new RealtimeEventQueue();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await using IAsyncEnumerator<BackendEvent> events = queue.ReadAllAsync(deadline.Token).GetAsyncEnumerator();
        for (int wave = 1; wave <= 2; wave++)
        {
            for (int i = 0; i < RealtimeEventQueue.Capacity + 1; i++)
                queue.TryWrite(new BackendEvent.Diagnostic("load"));
            var room = Guid.NewGuid();
            queue.TryWrite(new BackendEvent.RoomRevoked(room, wave));
            Assert.True(await events.MoveNextAsync());
            Assert.Equal(new BackendEvent.RoomRevoked(room, wave), events.Current);
            Assert.True(await events.MoveNextAsync());
            Assert.IsType<BackendEvent.Diagnostic>(events.Current);
            Assert.True(await events.MoveNextAsync());
            Assert.IsType<BackendEvent.ReconciliationRequired>(events.Current);
            // No successful recovery occurs before another independent revoke arrives.
        }
    }

    [Fact]
    public async Task RevocationSurvivesQueuedAndOverflowedControlsBeforeAnyReconciliation()
    {
        var queue = new RealtimeEventQueue();
        Guid first = Guid.NewGuid(), second = Guid.NewGuid();
        Assert.True(queue.TryWrite(new BackendEvent.RoomRevoked(first, 1)));
        for (int i = 0; i < RealtimeEventQueue.Capacity + 1; i++)
            queue.TryWrite(new BackendEvent.Diagnostic("load"));
        Assert.True(queue.TryWrite(new BackendEvent.RoomRevoked(first, 2)));
        Assert.True(queue.TryWrite(new BackendEvent.RoomRevoked(second, 3)));
        queue.Complete();
        var results = new List<BackendEvent>();
        await foreach (BackendEvent value in queue.ReadAllAsync(CancellationToken.None))
            results.Add(value);
        Assert.Equal(new BackendEvent.RoomRevoked(first, 2), results[0]);
        Assert.Equal(new BackendEvent.RoomRevoked(second, 3), results[1]);
        Assert.IsType<BackendEvent.ReconciliationRequired>(results[^1]);
        Assert.Equal(4, results.Count);
    }

    [Fact]
    public async Task ExcessiveDistinctRevocationsCollapseToOneBoundedAccessReset()
    {
        var queue = new RealtimeEventQueue();
        for (int i = 0; i < RealtimeEventQueue.Capacity * 3; i++)
            Assert.True(queue.TryWrite(new BackendEvent.RoomRevoked(Guid.NewGuid(), i + 1)));
        Assert.Equal(RealtimeEventQueue.Capacity, queue.Count);
        queue.Complete();
        var results = new List<BackendEvent>();
        await foreach (BackendEvent value in queue.ReadAllAsync(CancellationToken.None))
            results.Add(value);
        Assert.Equal(new BackendEvent.RoomAccessInvalidated(RealtimeEventQueue.Capacity * 3), results[0]);
        Assert.Equal(3, results.Count);
    }

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
