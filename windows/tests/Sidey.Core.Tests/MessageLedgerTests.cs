using Sidey.Core.Domain;

namespace Sidey.Core.Tests;

public sealed class MessageLedgerTests
{
    [Fact]
    public void EqualClockTimestampsKeepNewestOutboxAttemptWithoutUuidOrderingEviction()
    {
        var clock = new LedgerClock();
        var ledger = new MessageLedger(clock);
        Guid room = Guid.NewGuid(), sender = Guid.NewGuid();
        var staged = new List<Guid>();
        for (int i = 0; i < 100; i++)
        {
            MessageLedgerEntry newest = ledger.StageNew(room, sender, "same clock");
            staged.Add(newest.Id);
            ledger.Fail(newest.Id);
            // Canonical insert sorts presentation order; it must not reorder attempt age.
            ledger.Confirm(new ChatMessage(Guid.NewGuid(), room, sender, "confirmed", clock.Now));
            Assert.Contains(ledger.Entries, entry => entry.Id == newest.Id);
        }
        Assert.Equal(staged.TakeLast(50).ToHashSet(), [.. ledger.Entries.Where(entry => entry.State == MessageDeliveryState.Failed).Select(entry => entry.Id)]);
        clock.Now = clock.Now.AddDays(3);
        Assert.Null(ledger.RetryFailed(room, sender, staged[^1]));
        Assert.DoesNotContain(ledger.Entries, entry => entry.State != MessageDeliveryState.Confirmed);
    }

    [Fact]
    public void SameBodyFreshSendCreatesNewIdWhileExplicitRetryReusesOnlyChosenFailure()
    {
        var ledger = new MessageLedger();
        Guid room = Guid.NewGuid(), sender = Guid.NewGuid();
        MessageLedgerEntry first = ledger.StageNew(room, sender, "same body");
        ledger.Fail(first.Id);
        MessageLedgerEntry fresh = ledger.StageNew(room, sender, "same body");
        Assert.NotEqual(first.Id, fresh.Id);
        Assert.Equal(first.Id, ledger.RetryFailed(room, sender, first.Id)!.Id);
        Assert.Equal(2, ledger.Entries.Count);
        Assert.All(ledger.Entries, entry => Assert.Equal(MessageDeliveryState.Pending, entry.State));
    }

    [Fact]
    public void FailedAndPendingOutboxIsBoundedPerRoomAndExpiredIdsCannotBeRetried()
    {
        var clock = new LedgerClock();
        var ledger = new MessageLedger(clock);
        Guid room = Guid.NewGuid(), other = Guid.NewGuid(), sender = Guid.NewGuid();
        var ids = new List<Guid>();
        for (int i = 0; i < 80; i++)
        {
            MessageLedgerEntry entry = ledger.StageNew(room, sender, "pending");
            ids.Add(entry.Id);
            if (i % 2 == 0)
                ledger.Fail(entry.Id);
            clock.Now = clock.Now.AddSeconds(1);
        }
        MessageLedgerEntry retained = ledger.StageNew(other, sender, "other room");
        ledger.Fail(retained.Id);
        Assert.Equal(50, ledger.Entries.Count(entry => entry.RoomId == room));
        Assert.DoesNotContain(ledger.Entries, entry => ids.Take(30).Contains(entry.Id));
        Assert.Null(ledger.RetryFailed(room, sender, ids[0]));
        clock.Now = clock.Now.AddDays(3).AddTicks(1);
        Assert.Null(ledger.RetryFailed(other, sender, retained.Id));
        Assert.Empty(ledger.Entries);
    }

    private sealed class LedgerClock : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = DateTimeOffset.Parse("2026-09-17T00:00:00Z");
        public override DateTimeOffset GetUtcNow() => Now;
    }

    [Fact]
    public void RevokedRoomsAndLogoutRemoveBothPendingAndConfirmedPrivateMessages()
    {
        var ledger = new MessageLedger();
        var retained = Guid.NewGuid();
        var revoked = Guid.NewGuid();
        var sender = Guid.NewGuid();
        ledger.Stage(Guid.NewGuid(), revoked, sender, "pending private");
        ledger.Confirm(new ChatMessage(Guid.NewGuid(), revoked, sender, "committed private", DateTimeOffset.UtcNow));
        ledger.Stage(Guid.NewGuid(), retained, sender, "still accessible");
        ledger.RetainRooms(new HashSet<Guid> { retained });
        Assert.Single(ledger.Entries);
        Assert.Equal(retained, ledger.Entries[0].RoomId);
        ledger.Clear();
        Assert.Empty(ledger.Entries);
    }

    [Fact]
    public void FailedResendKeepsUuidAndFirstAttemptBubbleSnapshot()
    {
        var ledger = new MessageLedger();
        Guid id = Guid.NewGuid(), room = Guid.NewGuid(), sender = Guid.NewGuid();
        string bubbleStyleId = CosmeticCatalog.BubbleStyleIds.First();
        ledger.Stage(id, room, sender, "retry", bubbleStyleId: bubbleStyleId);
        MessageLedgerEntry original = Assert.Single(ledger.Entries);
        ledger.Fail(id);
        MessageLedgerEntry retry = Assert.IsType<MessageLedgerEntry>(ledger.RetryFailed(room, sender, id));
        Assert.Equal(id, retry.Id);
        Assert.Equal(bubbleStyleId, retry.BubbleStyleId);
        Assert.Equal(original.BubbleStyleId, retry.BubbleStyleId);
        Assert.Equal(original.CreatedAt, retry.CreatedAt);
        Assert.Equal(MessageDeliveryState.Pending, retry.State);
        Assert.Single(ledger.Entries);
        Assert.Null(ledger.RetryFailed(room, sender, id));
        ledger.Confirm(new ChatMessage(id, room, sender, "retry", DateTimeOffset.UtcNow));
        Assert.Equal(MessageDeliveryState.Confirmed, Assert.Single(ledger.Entries).State);
    }

    [Fact]
    public void RetryRequiresTheExactFailedIdRoomAndSender()
    {
        var ledger = new MessageLedger();
        Guid id = Guid.NewGuid(), room = Guid.NewGuid(), sender = Guid.NewGuid();
        ledger.Stage(id, room, sender, "original");
        ledger.Fail(id);
        Assert.Null(ledger.RetryFailed(room, sender, Guid.NewGuid()));
        Assert.Null(ledger.RetryFailed(Guid.NewGuid(), sender, id));
        Assert.Null(ledger.RetryFailed(room, Guid.NewGuid(), id));
        Assert.Equal(MessageDeliveryState.Failed, Assert.Single(ledger.Entries).State);
    }
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
        MessageLedgerEntry entry = Assert.Single(ledger.Entries);
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
    public void FailedOptimisticMessageReturnsBodyAndKeepsFailedEntry()
    {
        var id = Guid.NewGuid();
        var ledger = new MessageLedger();
        ledger.Stage(id, Guid.NewGuid(), Guid.NewGuid(), "복구할 메시지");

        Assert.Equal("복구할 메시지", ledger.Fail(id));
        MessageLedgerEntry failed = Assert.Single(ledger.Entries);
        Assert.Equal(MessageDeliveryState.Failed, failed.State);
        Assert.Equal("복구할 메시지", failed.Body);
        Assert.Null(ledger.Fail(id));
    }

    [Fact]
    public void ServerDeletionRemovesOnlyTheMatchingRoomMessage()
    {
        var roomId = Guid.NewGuid();
        var messageId = Guid.NewGuid();
        var otherMessageId = Guid.NewGuid();
        var ledger = new MessageLedger();
        ledger.Confirm(new ChatMessage(
            messageId, roomId, Guid.NewGuid(), "삭제 대상", DateTimeOffset.UtcNow));
        ledger.Confirm(new ChatMessage(
            otherMessageId, Guid.NewGuid(), Guid.NewGuid(), "다른 방", DateTimeOffset.UtcNow));

        Assert.True(ledger.Remove(roomId, messageId));
        Assert.Single(ledger.Entries);
        Assert.Equal(otherMessageId, ledger.Entries[0].Id);
        Assert.False(ledger.Remove(roomId, messageId));
    }

    [Fact]
    public void ConfirmedHistoryIsBoundedPerRoomAndPendingRowsSurvivePruning()
    {
        var roomId = Guid.NewGuid();
        var senderId = Guid.NewGuid();
        var ledger = new MessageLedger();
        DateTimeOffset start = DateTimeOffset.UtcNow.AddMinutes(-2);
        for (int index = 0; index < 51; index++)
        {
            ledger.Confirm(new ChatMessage(
                Guid.NewGuid(),
                roomId,
                senderId,
                $"메시지 {index}",
                start.AddSeconds(index)));
        }
        var pendingId = Guid.NewGuid();
        ledger.Stage(pendingId, roomId, senderId, "전송 중");

        ledger.PruneConfirmed();

        Assert.Equal(MessageLedger.MaximumConfirmedPerRoom + 1, ledger.Entries.Count);
        Assert.Contains(ledger.Entries, entry =>
            entry.Id == pendingId && entry.State == MessageDeliveryState.Pending);
    }

    [Fact]
    public void ConfirmedHistoryUsesThreeDayBoundary()
    {
        var roomId = Guid.NewGuid();
        var senderId = Guid.NewGuid();
        var now = DateTimeOffset.FromUnixTimeSeconds(1_000_000);
        var expiredId = Guid.NewGuid();
        var boundaryId = Guid.NewGuid();
        var recentId = Guid.NewGuid();
        var ledger = new MessageLedger(new LedgerClock { Now = now });

        ledger.Confirm(new ChatMessage(
            expiredId,
            roomId,
            senderId,
            "만료",
            now - MessageLedger.ConfirmedRetention - TimeSpan.FromSeconds(1)), now);
        ledger.Confirm(new ChatMessage(
            boundaryId,
            roomId,
            senderId,
            "경계",
            now - MessageLedger.ConfirmedRetention), now);
        ledger.Confirm(new ChatMessage(
            recentId,
            roomId,
            senderId,
            "최근",
            now - TimeSpan.FromDays(2)), now);

        Assert.Equal(TimeSpan.FromDays(3), MessageLedger.ConfirmedRetention);
        Assert.DoesNotContain(ledger.Entries, entry => entry.Id == expiredId);
        Assert.Contains(ledger.Entries, entry => entry.Id == boundaryId);
        Assert.Contains(ledger.Entries, entry => entry.Id == recentId);
    }

    [Fact]
    public void ActiveBubblesKeepTwoPerSenderWithoutGlobalEviction()
    {
        var ledger = new ActiveBubbleLedger();
        var start = DateTimeOffset.FromUnixTimeSeconds(1_000);
        Guid[] senders = [.. Enumerable.Range(0, 12).Select(_ => Guid.NewGuid())];

        for (int index = 0; index < senders.Length; index++)
        {
            ledger.Show(
                senders[index],
                Guid.NewGuid(),
                $"이전 {index}",
                start.AddSeconds(index + 1));
            ledger.Show(
                senders[index],
                Guid.NewGuid(),
                $"최신 {index}",
                start.AddSeconds(index + 20));
        }

        Assert.Equal(24, ledger.Bubbles.Count);
        Assert.All(senders, sender =>
            Assert.Equal(2, ledger.Bubbles.Count(bubble => bubble.SenderId == sender)));
    }

    [Fact]
    public void ThirdBubbleEvictsOnlyThatSendersOldestAndExpiryIsIndependent()
    {
        var ledger = new ActiveBubbleLedger();
        var start = DateTimeOffset.FromUnixTimeSeconds(1_000);
        var sender = Guid.NewGuid();
        var otherSender = Guid.NewGuid();
        var oldestId = Guid.NewGuid();
        var middleId = Guid.NewGuid();
        var latestId = Guid.NewGuid();
        var otherId = Guid.NewGuid();

        ledger.Show(sender, oldestId, "첫 번째", start.AddSeconds(1));
        ledger.Show(sender, middleId, "두 번째", start.AddSeconds(20));
        ledger.Show(otherSender, otherId, "다른 친구", start.AddSeconds(30));
        ledger.Show(sender, latestId, "세 번째", start.AddSeconds(40));

        Assert.DoesNotContain(ledger.Bubbles, bubble => bubble.MessageId == oldestId);
        Assert.Contains(ledger.Bubbles, bubble => bubble.MessageId == middleId);
        Assert.Contains(ledger.Bubbles, bubble => bubble.MessageId == latestId);
        Assert.Contains(ledger.Bubbles, bubble => bubble.MessageId == otherId);

        ledger.Prune(start.AddSeconds(25));

        Assert.DoesNotContain(ledger.Bubbles, bubble => bubble.MessageId == middleId);
        Assert.Contains(ledger.Bubbles, bubble => bubble.MessageId == latestId);
        Assert.Contains(ledger.Bubbles, bubble => bubble.MessageId == otherId);
    }
}
