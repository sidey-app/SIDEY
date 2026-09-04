using Sidey.Infrastructure;

namespace Sidey.Platform.Windows.Tests;

public sealed class ExpiringLeaseRegistryTests
{
    [Fact]
    public async Task RestartCancelsThePreviousLeaseAndExpiresOnlyTheLatest()
    {
        var firstDelay = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var secondDelay = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var expired = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        var delayCalls = new Queue<TaskCompletionSource>([firstDelay, secondDelay]);
        await using var registry = new ExpiringLeaseRegistry<string>(
            TimeSpan.FromSeconds(4),
            key => expired.TrySetResult(key),
            (_, cancellationToken) => delayCalls.Dequeue().Task.WaitAsync(cancellationToken));

        registry.Restart("friend");
        registry.Restart("friend");
        secondDelay.SetResult();

        Assert.Equal("friend", await expired.Task.WaitAsync(TimeSpan.FromSeconds(1)));
        Assert.Equal(0, registry.Count);
        Assert.True(firstDelay.Task.IsCompletedSuccessfully is false);
    }

    [Fact]
    public async Task CancelPreventsExpiryCallback()
    {
        var delay = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var expiryCount = 0;
        await using var registry = new ExpiringLeaseRegistry<string>(
            TimeSpan.FromSeconds(4),
            _ => Interlocked.Increment(ref expiryCount),
            (_, cancellationToken) => delay.Task.WaitAsync(cancellationToken));

        registry.Restart("friend");
        registry.Cancel("friend");
        delay.SetResult();
        await Task.Yield();

        Assert.Equal(0, registry.Count);
        Assert.Equal(0, Volatile.Read(ref expiryCount));
    }

    [Fact]
    public async Task DisposeCancelsAndAwaitsOutstandingLeases()
    {
        var delay = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var registry = new ExpiringLeaseRegistry<string>(
            TimeSpan.FromSeconds(4),
            _ => throw new InvalidOperationException("A disposed registry must not expire a lease."),
            (_, cancellationToken) => delay.Task.WaitAsync(cancellationToken));
        registry.Restart("friend");

        await registry.DisposeAsync();

        Assert.Equal(0, registry.Count);
        Assert.Throws<ObjectDisposedException>(() => registry.Restart("friend"));
    }
}
