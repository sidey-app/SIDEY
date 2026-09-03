using Sidey.Core.Domain;
using Sidey.Core.Realtime;

namespace Sidey.Core.Tests;

public sealed class RealtimePolicyTests
{
    [Fact]
    public void ConnectionRequiresEveryDesiredRoomAndDropsRemovedRooms()
    {
        var first = Guid.NewGuid();
        var second = Guid.NewGuid();
        var tracker = new RealtimeConnectionTracker();
        tracker.ReplaceDesiredRoomIds([first, second]);
        tracker.SetSubscribed(true, first);
        Assert.False(tracker.IsConnected);
        tracker.SetSubscribed(true, second);
        Assert.True(tracker.IsConnected);

        tracker.ReplaceDesiredRoomIds([second]);
        Assert.True(tracker.IsConnected);
        Assert.DoesNotContain(first, tracker.SubscribedRoomIds);
    }

    [Fact]
    public void PresenceJoinWinsOverLeaveInSameDelta()
    {
        var replaced = Guid.NewGuid();
        var departed = Guid.NewGuid();

        var updates = PresenceChangePlan.Updates(
            new Dictionary<Guid, PresenceState> { [replaced] = PresenceState.Away },
            new HashSet<Guid> { replaced, departed });

        Assert.Contains(updates, update => update.UserId == replaced && update.State == PresenceState.Away);
        Assert.DoesNotContain(updates, update => update.UserId == replaced && update.State == PresenceState.Offline);
        Assert.Contains(updates, update => update.UserId == departed && update.State == PresenceState.Offline);
    }

    [Fact]
    public void PresencePublicationUsesOnlyActiveRoom()
    {
        var active = Guid.NewGuid();
        Assert.Equal(PresenceState.Online, PresencePublicationPlan.StateFor(active, active, PresenceState.Typing));
        Assert.Equal(PresenceState.Away, PresencePublicationPlan.StateFor(active, active, PresenceState.Away));
        Assert.Equal(PresenceState.Offline, PresencePublicationPlan.StateFor(Guid.NewGuid(), active, PresenceState.Online));
    }

    [Fact]
    public void LocalPresenceCannotBeOverwrittenByAnOfflineSnapshotOrStaleEvent()
    {
        var currentUser = Guid.NewGuid();

        Assert.Equal(
            PresenceState.Online,
            LocalPresenceProjection.ForMember(
                currentUser,
                currentUser,
                PresenceState.Offline,
                PresenceState.Online));
        Assert.Equal(
            PresenceState.Offline,
            LocalPresenceProjection.ForMember(
                Guid.NewGuid(),
                currentUser,
                PresenceState.Offline,
                PresenceState.Online));
        var remoteUser = Guid.NewGuid();
        Assert.Equal(
            PresenceState.Online,
            LocalPresenceProjection.ForSnapshotMember(
                remoteUser,
                currentUser,
                PresenceState.Offline,
                PresenceState.Online,
                PresenceState.Online));
    }

    [Theory]
    [InlineData(PresenceState.Online, PresenceState.Reconnecting, PresenceState.Online)]
    [InlineData(PresenceState.Typing, PresenceState.Reconnecting, PresenceState.Online)]
    [InlineData(PresenceState.Away, PresenceState.Reconnecting, PresenceState.Away)]
    [InlineData(PresenceState.Reconnecting, PresenceState.Offline, PresenceState.Reconnecting)]
    [InlineData(PresenceState.Offline, PresenceState.Offline, PresenceState.Offline)]
    public void PresenceAggregationPrefersTheMostAvailableConnection(
        PresenceState first,
        PresenceState second,
        PresenceState expected)
    {
        Assert.Equal(expected, PresenceAggregatePlan.MostAvailable([first, second]));
    }

    [Fact]
    public void TypingLeaseStopsPreviousRoomBeforeStartingNext()
    {
        var first = Guid.NewGuid();
        var second = Guid.NewGuid();
        var lease = new TypingLease();

        Assert.Equal([new TypingLeaseAction.Start(first)], lease.Update(true, first));
        Assert.Empty(lease.Update(true, first));
        Assert.Equal(
            [new TypingLeaseAction.Stop(first), new TypingLeaseAction.Start(second)],
            lease.Update(true, second));
        Assert.Equal([new TypingLeaseAction.Stop(second)], lease.Update(false, second));
        Assert.Empty(lease.Update(false, null));
        Assert.Equal(TimeSpan.FromSeconds(2), TypingLease.KeepaliveInterval);
        Assert.Equal(TimeSpan.FromSeconds(4), TypingLease.RemoteExpiry);
    }

    [Fact]
    public void PulseCooldownIsPerRoomAndUser()
    {
        var roomId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var cooldown = new CharacterPulseCooldown();

        Assert.True(cooldown.Accept(roomId, userId, TimeSpan.FromSeconds(100)));
        Assert.False(cooldown.Accept(roomId, userId, TimeSpan.FromSeconds(100.999)));
        Assert.True(cooldown.Accept(roomId, userId, TimeSpan.FromSeconds(101)));
        Assert.True(cooldown.Accept(roomId, Guid.NewGuid(), TimeSpan.FromSeconds(101)));
        Assert.False(cooldown.Accept(roomId, userId, TimeSpan.FromSeconds(-1)));
    }

    [Fact]
    public void ThrowCooldownMatchesTheHalfSecondClientContract()
    {
        var roomId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var cooldown = new CharacterThrowCooldown();

        Assert.True(cooldown.Accept(roomId, userId, TimeSpan.FromSeconds(10)));
        Assert.False(cooldown.Accept(roomId, userId, TimeSpan.FromSeconds(10.499)));
        Assert.True(cooldown.Accept(roomId, userId, TimeSpan.FromSeconds(10.5)));
        Assert.True(cooldown.Accept(roomId, Guid.NewGuid(), TimeSpan.FromSeconds(10.5)));
        Assert.False(cooldown.Accept(roomId, userId, TimeSpan.FromSeconds(-1)));
        Assert.Equal(TimeSpan.FromMilliseconds(500), CharacterThrowCooldown.Duration);
    }

    [Theory]
    [InlineData(PresenceState.Online)]
    [InlineData(PresenceState.Typing)]
    [InlineData(PresenceState.Away)]
    [InlineData(PresenceState.Offline)]
    [InlineData(PresenceState.Reconnecting)]
    public void ThrowTargetIgnoresPresence(PresenceState presence)
    {
        Assert.True(CharacterThrowTargetPolicy.CanTarget(new PixelWorldMember(
            Guid.NewGuid(), "friend", "pixel_hamster", presence, false, false)));
        Assert.False(CharacterThrowTargetPolicy.CanTarget(new PixelWorldMember(
            Guid.NewGuid(), "self", "pixel_hamster", presence, false, true)));
    }

    [Theory]
    [InlineData(1, 8)]
    [InlineData(2, 16)]
    [InlineData(3, 30)]
    [InlineData(99, 30)]
    public void RealtimeBackoffMatchesTheMacContract(int attempt, int seconds)
    {
        Assert.Equal(TimeSpan.FromSeconds(seconds), RealtimeRecoveryPolicy.DelayForAttempt(attempt));
        Assert.Equal(TimeSpan.FromSeconds(5), RealtimeRecoveryPolicy.WatchdogInterval);
    }
}
