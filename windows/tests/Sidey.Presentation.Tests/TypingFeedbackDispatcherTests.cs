using Sidey.Presentation.Services;

namespace Sidey.Presentation.Tests;

public sealed class TypingFeedbackDispatcherTests
{
    [Fact]
    public void TimerPublicationWaitsForPresentationThread()
    {
        var pending = new Queue<Action>();
        var rendered = new List<bool>();
        using var feedback = new TypingFeedbackDispatcher(pending.Enqueue, (_, active) => rendered.Add(active));
        feedback.Publish(Guid.NewGuid(), false);
        Assert.Empty(rendered);
        pending.Dequeue()();
        Assert.Equal([false], rendered);
    }

    [Fact]
    public void QueuedIdleStopCannotEraseNewImmediateEdit()
    {
        var pending = new Queue<Action>();
        var rendered = new List<bool>();
        bool ownerThread = false;
        using var feedback = new TypingFeedbackDispatcher(
            action => { if (ownerThread) action(); else pending.Enqueue(action); },
            (_, active) => rendered.Add(active));
        var room = Guid.NewGuid();
        feedback.Publish(room, false);
        ownerThread = true;
        feedback.Publish(room, true);
        Assert.Equal([true], rendered);
        pending.Dequeue()();
        Assert.Equal([true], rendered);
    }

    [Fact]
    public void DisposalDropsQueuedAndFutureOverlayAccess()
    {
        var pending = new Queue<Action>();
        using var feedback = new TypingFeedbackDispatcher(pending.Enqueue, (_, _) =>
            throw new InvalidOperationException("Disposed overlay accessed"));
        feedback.Publish(Guid.NewGuid(), false);
        feedback.Dispose();
        pending.Dequeue()();
        feedback.Publish(Guid.NewGuid(), true);
        Assert.Empty(pending);
    }
}
