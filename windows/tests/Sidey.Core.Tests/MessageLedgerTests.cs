using Sidey.Core.Domain;

namespace Sidey.Core.Tests;

public sealed class MessageLedgerTests
{
    [Fact]
    public void OptimisticMessageConfirmsWithoutRealtimeDuplicate()
    {
        var id = Guid.NewGuid();
        var roomId = Guid.NewGuid();
        var senderId = Guid.NewGuid();
        var ledger = new MessageLedger();
        var message = new ChatMessage(id, roomId, senderId, "안녕", DateTimeOffset.UtcNow);

        ledger.Stage(id, roomId, senderId, "안녕");

        Assert.False(ledger.Confirm(message));
        Assert.False(ledger.Confirm(message));
        var entry = Assert.Single(ledger.Entries);
        Assert.Equal(senderId, entry.SenderId);
        Assert.Equal(MessageDeliveryState.Confirmed, entry.State);
    }

    [Fact]
    public void ReplacingHistoryKeepsPendingAndDeduplicatesConfirmedRows()
    {
        var roomId = Guid.NewGuid();
        var pendingId = Guid.NewGuid();
        var confirmed = new ChatMessage(
            Guid.NewGuid(), roomId, Guid.NewGuid(), "서버 원본", DateTimeOffset.UtcNow);
        var ledger = new MessageLedger();
        ledger.Stage(pendingId, roomId, Guid.NewGuid(), "전송 중");

        ledger.ReplaceConfirmed(roomId, [confirmed, confirmed]);

        Assert.Equal(2, ledger.Entries.Count);
        Assert.Contains(ledger.Entries, entry => entry.Id == pendingId && entry.State == MessageDeliveryState.Pending);
        Assert.Single(ledger.Entries, entry => entry.Id == confirmed.Id);
    }

    [Fact]
    public void FailedOptimisticMessageReturnsBodyAndRemovesEntry()
    {
        var id = Guid.NewGuid();
        var ledger = new MessageLedger();
        ledger.Stage(id, Guid.NewGuid(), Guid.NewGuid(), "복구할 메시지");

        Assert.Equal("복구할 메시지", ledger.Fail(id));
        Assert.Empty(ledger.Entries);
        Assert.Null(ledger.Fail(id));
    }

    [Fact]
    public void ActiveBubblesReplacePerSenderEvictOldestAndExpireIndependently()
    {
        var ledger = new ActiveBubbleLedger();
        var start = DateTimeOffset.FromUnixTimeSeconds(1_000);
        var senders = Enumerable.Range(0, 5).Select(_ => Guid.NewGuid()).ToArray();

        for (var index = 0; index < 4; index++)
        {
            ledger.Show(senders[index], Guid.NewGuid(), $"메시지 {index}", start.AddSeconds(index + 1));
        }

        var replacementId = Guid.NewGuid();
        ledger.Show(senders[0], replacementId, "교체", start.AddSeconds(20));
        Assert.Equal(4, ledger.Bubbles.Count);
        Assert.Contains(ledger.Bubbles, bubble => bubble.SenderId == senders[0] && bubble.MessageId == replacementId);

        ledger.Show(senders[4], Guid.NewGuid(), "다섯 번째", start.AddSeconds(21));
        Assert.Equal(4, ledger.Bubbles.Count);
        Assert.DoesNotContain(ledger.Bubbles, bubble => bubble.SenderId == senders[1]);

        ledger.Prune(start.AddSeconds(20.5));
        Assert.Equal(senders[4], Assert.Single(ledger.Bubbles).SenderId);
    }
}
