using Sidey.Presentation.Services;

namespace Sidey.Presentation.Tests;

public sealed class DelayedActionTests
{
    [Fact]
    public async Task CancelAfterCompletionIsSafeAndDoesNotRepeatAction()
    {
        int calls = 0;
        var action = DelayedAction.Start(TimeSpan.FromMilliseconds(10), () => calls++);

        await action.Completion.WaitAsync(TimeSpan.FromSeconds(5));
        action.Cancel();
        action.Cancel();

        Assert.Equal(1, calls);
    }

    [Fact]
    public async Task RepeatedCancellationSuppressesPendingAction()
    {
        int calls = 0;
        var action = DelayedAction.Start(TimeSpan.FromSeconds(30), () => calls++);

        action.Cancel();
        action.Cancel();
        await action.Completion.WaitAsync(TimeSpan.FromSeconds(5));
        action.Cancel();

        Assert.Equal(0, calls);
    }

    [Fact]
    public async Task ConcurrentCancellationAndCompletionAreSafe()
    {
        for (int iteration = 0; iteration < 100; iteration++)
        {
            int calls = 0;
            var action = DelayedAction.Start(
                TimeSpan.FromMilliseconds(1), () => Interlocked.Increment(ref calls));

            await Task.WhenAll(
                action.Completion,
                Task.Run(action.Cancel),
                Task.Run(action.Cancel)).WaitAsync(TimeSpan.FromSeconds(5));
            action.Cancel();

            Assert.InRange(calls, 0, 1);
        }
    }
}
