using Sidey.Core.Realtime;

namespace Sidey.Core.Tests;

public sealed class RoomSessionLifetimeTests
{
    [Fact]
    public async Task DisposalWaitsForReplacedTypingAndBothPumps()
    {
        var session = new RoomSessionLifetime();
        var drained = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var cancellationObserved = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        session.StartTyping(async token =>
        {
            try
            { await Task.Delay(Timeout.Infinite, token); }
            catch (OperationCanceledException) { cancellationObserved.SetResult(); }
            await drained.Task;
        });
        session.StartTyping(token => Task.Delay(Timeout.Infinite, token));
        await cancellationObserved.Task.WaitAsync(TimeSpan.FromSeconds(2));
        session.EventPump = Task.Delay(Timeout.Infinite, session.Token);
        session.ActivityPump = Task.Delay(Timeout.Infinite, session.Token);
        Task disposal = session.DisposeAsync().AsTask();
        Assert.True(session.Token.IsCancellationRequested);
        Assert.False(disposal.IsCompleted);
        drained.SetResult();
        await disposal.WaitAsync(TimeSpan.FromSeconds(2));
        await session.DisposeAsync();
        Assert.Throws<ObjectDisposedException>(() => session.StartTyping(_ => Task.CompletedTask));
    }

    [Fact]
    public async Task StopTypingDoesNotCancelRoomWork()
    {
        await using var session = new RoomSessionLifetime();
        session.StartTyping(token => Task.Delay(Timeout.Infinite, token));
        session.StopTyping();
        session.StopTyping();
        Assert.False(session.Token.IsCancellationRequested);
    }
}
