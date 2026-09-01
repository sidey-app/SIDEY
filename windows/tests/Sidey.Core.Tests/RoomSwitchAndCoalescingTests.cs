using Sidey.Core.Domain;
using Sidey.Core.Realtime;

namespace Sidey.Core.Tests;

public sealed class RoomSwitchAndCoalescingTests
{
    [Fact]
    public async Task RoomSwitchSerializesNetworkAndOnlyCommitsLatestRequest()
    {
        var first = Guid.NewGuid();
        var second = Guid.NewGuid();
        var firstStarted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseFirst = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var commits = new List<Guid>();
        var activeNetworkCalls = 0;
        var maximumNetworkCalls = 0;

        await using var pipeline = new RoomSwitchPipeline(
            async (roomId, _) =>
            {
                var active = Interlocked.Increment(ref activeNetworkCalls);
                maximumNetworkCalls = Math.Max(maximumNetworkCalls, active);
                try
                {
                    if (roomId == first)
                    {
                        firstStarted.TrySetResult();
                        await releaseFirst.Task;
                    }
                    return Array.Empty<ChatMessage>();
                }
                finally
                {
                    Interlocked.Decrement(ref activeNetworkCalls);
                }
            },
            (_, _) => Task.CompletedTask,
            (roomId, _) => commits.Add(roomId),
            TimeSpan.Zero);

        var firstRequest = pipeline.RequestAsync(first);
        await firstStarted.Task;
        var secondRequest = pipeline.RequestAsync(second);
        releaseFirst.TrySetResult();
        await Task.WhenAll(firstRequest, secondRequest);

        Assert.Equal(1, maximumNetworkCalls);
        Assert.Equal([second], commits);
        Assert.Equal(second, pipeline.CommittedRoomId);
    }

    [Fact]
    public async Task FailedLatestSwitchRestoresThePreviouslyCommittedRoom()
    {
        var committed = Guid.NewGuid();
        Guid? restored = null;
        await using var pipeline = new RoomSwitchPipeline(
            (_, _) => throw new InvalidOperationException("network failed"),
            (roomId, _) =>
            {
                restored = roomId;
                return Task.CompletedTask;
            },
            (_, _) => { },
            TimeSpan.Zero);
        pipeline.InitializeCommittedRoom(committed);

        await Assert.ThrowsAsync<InvalidOperationException>(() =>
            pipeline.RequestAsync(Guid.NewGuid()));

        Assert.Equal(committed, restored);
        Assert.Equal(committed, pipeline.CommittedRoomId);
    }

    [Fact]
    public async Task PresencePublicationsAreSerialAndPendingWorkCoalescesToLatest()
    {
        var firstStarted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseFirst = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var published = new List<int>();
        var active = 0;
        var maximumActive = 0;
        await using var queue = new CoalescingPublicationQueue<int>(async (value, _) =>
        {
            var current = Interlocked.Increment(ref active);
            maximumActive = Math.Max(maximumActive, current);
            try
            {
                published.Add(value);
                if (value == 1)
                {
                    firstStarted.TrySetResult();
                    await releaseFirst.Task;
                }
            }
            finally
            {
                Interlocked.Decrement(ref active);
            }
        });

        var first = queue.SubmitAsync(1);
        await firstStarted.Task;
        var superseded = queue.SubmitAsync(2);
        var latest = queue.SubmitAsync(3);
        releaseFirst.TrySetResult();
        await Task.WhenAll(first, superseded, latest);

        Assert.Equal([1, 3], published);
        Assert.Equal(1, maximumActive);
    }
}
