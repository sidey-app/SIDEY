using Sidey.Core.Domain;
using Sidey.Core.Realtime;

namespace Sidey.Core.Tests;

public sealed class RealtimePolicyTests
{
    [Fact]
    public void RoomPlanCapsDesiredSubscriptionsAtFive()
    {
        var requested = Enumerable.Range(0, 6).Select(_ => Guid.NewGuid()).ToArray();

        var plan = RealtimeRoomPlan.Create(new HashSet<Guid>(), requested, requested[5]);

        Assert.Equal(5, plan.Desired.Count);
        Assert.Null(plan.ActiveRoomId);
    }

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
        Assert.False(cooldown.Accept(roomId, userId, TimeSpan.FromSeconds(109.999)));
        Assert.True(cooldown.Accept(roomId, userId, TimeSpan.FromSeconds(110)));
        Assert.True(cooldown.Accept(roomId, Guid.NewGuid(), TimeSpan.FromSeconds(101)));
        Assert.False(cooldown.Accept(roomId, userId, TimeSpan.FromSeconds(-1)));
    }
}
