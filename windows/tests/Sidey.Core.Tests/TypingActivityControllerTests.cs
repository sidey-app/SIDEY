using Sidey.Core.Realtime;
using Xunit.Abstractions;

namespace Sidey.Core.Tests;

public sealed class TypingActivityControllerTests(ITestOutputHelper output)
{
    private static readonly Guid Room = Guid.NewGuid();

    [Fact]
    public async Task ShortEditShowsLocallyWithoutRemoteStart()
    {
        var clock = new ManualClock();
        var remote = new List<bool>();
        var local = new List<bool>();
        await using var controller = new TypingActivityController(
            (_, active, _, _) => { remote.Add(active); return Task.CompletedTask; },
            (_, active) => local.Add(active), clock);
        controller.Edit(Room);
        Assert.Equal([true], local);
        clock.Advance(499);
        controller.Stop();
        clock.Advance(6000);
        Assert.Empty(remote);
        Assert.Equal([true, false], local);
    }

    [Fact]
    public async Task ContinuousEditsKeepFirstDeadlineAndThrottleRefresh()
    {
        var clock = new ManualClock();
        var calls = new List<(long At, bool Active)>();
        await using var controller = new TypingActivityController(
            (_, active, _, _) => { calls.Add((clock.Milliseconds, active)); return Task.CompletedTask; }, (_, _) => { }, clock);
        controller.Edit(Room);
        for (int index = 0; index < 30; index++)
        {
            clock.Advance(100);
            controller.Edit(Room);
        }
        Assert.Equal([(500L, true), (2500L, true)], calls);
        clock.Advance(2000);
        Assert.Equal((4500L, true), calls[^1]);
        clock.Advance(2999);
        Assert.Equal(3, calls.Count);
        clock.Advance(1);
        Assert.Equal((8000L, false), calls[^1]);
    }

    [Fact]
    public async Task IdleDoesNotRefreshAndEndsFiveSecondsAfterActualEdit()
    {
        var clock = new ManualClock();
        var calls = new List<(long At, bool Active)>();
        await using var controller = new TypingActivityController(
            (_, active, _, _) => { calls.Add((clock.Milliseconds, active)); return Task.CompletedTask; }, (_, _) => { }, clock);
        controller.Edit(Room);
        clock.Advance(10000);
        Assert.Equal([(500L, true), (5000L, false)], calls);
    }

    [Fact]
    public async Task PendingStartIsFollowedByOldRoomStopBeforeNewRoomStart()
    {
        var clock = new ManualClock();
        var first = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var newStarted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var second = Guid.NewGuid();
        var calls = new List<(Guid Room, bool Active)>();
        await using var controller = new TypingActivityController((room, active, _, _) =>
        {
            calls.Add((room, active));
            if (calls.Count == 1)
                return first.Task;
            if (room == second && active)
                newStarted.TrySetResult();
            return Task.CompletedTask;
        }, (_, _) => { }, clock);
        controller.Edit(Room);
        clock.Advance(500);
        controller.Stop();
        controller.Edit(second);
        clock.Advance(500);
        Assert.Single(calls);
        first.SetException(new IOException("delayed transient failure"));
        await newStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal([(Room, true), (Room, false), (second, true)], calls);
    }

    [Fact]
    public async Task FailureNeedsNewEditAndNeverAutomaticallyReplays()
    {
        var clock = new ManualClock();
        int starts = 0;
        await using var controller = new TypingActivityController((_, active, _, _) =>
        {
            if (active)
                starts++;
            return Task.FromException(new IOException("offline"));
        }, (_, _) => { }, clock);
        controller.Edit(Room);
        clock.Advance(3000);
        Assert.Equal(1, starts);
        controller.Edit(Room);
        clock.Advance(0);
        Assert.Equal(2, starts);
        clock.Advance(5000);
        Assert.Equal(2, starts);
    }

    [Fact]
    public async Task StopDuringRequestEndsLocalFeedbackAtIdleDeadline()
    {
        var clock = new ManualClock();
        var response = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var local = new List<(long At, bool Active)>();
        await using var controller = new TypingActivityController(
            (_, active, _, _) => active ? response.Task : Task.CompletedTask,
            (_, active) => local.Add((clock.Milliseconds, active)), clock);
        controller.Edit(Room);
        clock.Advance(5000);
        Assert.Equal([(0L, true), (5000L, false)], local);
        response.SetResult();
    }

    [Fact]
    public async Task CanceledQueuedStartNeverReplaysAfterPreviousRequestCompletes()
    {
        var clock = new ManualClock();
        var response = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var stopped = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var calls = new List<bool>();
        await using var controller = new TypingActivityController((_, active, _, _) =>
        {
            calls.Add(active);
            if (active)
                return response.Task;
            stopped.TrySetResult();
            return Task.CompletedTask;
        }, (_, _) => { }, clock);
        controller.Edit(Room);
        clock.Advance(500);
        controller.Stop();
        controller.Edit(Room);
        clock.Advance(500);
        controller.Stop();
        response.SetResult();
        await stopped.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await controller.DisposeAsync();
        Assert.Equal([true, false], calls);
        clock.Advance(10000);
        Assert.Equal(2, calls.Count);
    }

    [Theory]
    [InlineData("short", 1, 0, 1, 0, 0, 0)]
    [InlineData("idle", 1, 5, 1, 1, 0, 1)]
    [InlineData("continuous", 1, 4, 1, 1, 2, 1)]
    public async Task SameInputTraceRecordsLegacyAndOptimizedPublicationCounts(
        string trace, int oldStart, int oldRefresh, int oldStop, int newStart, int newRefresh, int newStop)
    {
        var clock = new ManualClock();
        var baseline = new TypingLease();
        int starts = 0, refreshes = 0, stops = 0;
        int baselineStarts = 0, baselineRefreshes = 0, baselineStops = 0;
        // Replays the previous coordinator's immediate lease + unconditional 2-second loop,
        // with synchronous successful sends; these are publisher calls, not billable deliveries.
        using ITimer keepalive = clock.CreateTimer(_ => baselineRefreshes++, null,
            Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
        await using var controller = new TypingActivityController((_, active, refresh, _) =>
        {
            if (!active)
                stops++;
            else if (refresh)
                refreshes++;
            else
                starts++;
            return Task.CompletedTask;
        }, (_, _) => { }, clock);
        void Edit()
        {
            foreach (TypingLeaseAction action in baseline.Update(true, Room))
            {
                if (action is TypingLeaseAction.Start)
                {
                    baselineStarts++;
                    keepalive.Change(TypingLease.KeepaliveInterval, TypingLease.KeepaliveInterval);
                }
            }
            controller.Edit(Room);
        }
        Edit();
        if (trace == "continuous")
        {
            for (int index = 0; index < 30; index++)
            {
                clock.Advance(100);
                Edit();
            }
        }
        clock.Advance(trace == "short" ? 499 : trace == "idle" ? 10001 : 5001);
        baselineStops += baseline.Update(false, Room).Count;
        keepalive.Change(Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
        controller.Stop();
        Assert.Equal((oldStart, oldRefresh, oldStop), (baselineStarts, baselineRefreshes, baselineStops));
        Assert.Equal((newStart, newRefresh, newStop), (starts, refreshes, stops));
        output.WriteLine($"{trace}: legacy start/refresh/stop={baselineStarts}/{baselineRefreshes}/{baselineStops}; "
            + $"optimized={starts}/{refreshes}/{stops}");
    }

    private sealed class ManualClock : TimeProvider
    {
        private readonly List<ManualTimer> _timers = [];
        public long Milliseconds { get; private set; }
        public override long TimestampFrequency => 1000;
        public override long GetTimestamp() => Milliseconds;
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        {
            var timer = new ManualTimer(this, callback, state);
            _timers.Add(timer);
            timer.Change(dueTime, period);
            return timer;
        }
        public void Advance(long milliseconds)
        {
            long target = Milliseconds + milliseconds;
            while (_timers.Where(timer => timer.Due <= target).MinBy(timer => timer.Due) is { } next)
            {
                Milliseconds = next.Due;
                next.Due = next.Period > 0 ? Milliseconds + next.Period : long.MaxValue;
                next.Fire();
            }
            Milliseconds = target;
        }
        private sealed class ManualTimer(ManualClock clock, TimerCallback callback, object? state) : ITimer
        {
            public long Due { get; set; } = long.MaxValue;
            public long Period { get; private set; }
            public bool Change(TimeSpan dueTime, TimeSpan period)
            {
                Period = (long)period.TotalMilliseconds;
                Due = dueTime == Timeout.InfiniteTimeSpan ? long.MaxValue : clock.Milliseconds + (long)dueTime.TotalMilliseconds;
                return true;
            }
            public void Fire() => callback(state);
            public void Dispose() => Due = long.MaxValue;
            public ValueTask DisposeAsync() { Dispose(); return ValueTask.CompletedTask; }
        }
    }
}
