using Sidey.Core.Realtime;

namespace Sidey.Core.Tests;

public sealed class RealtimeRoomPlanTests
{
    [Fact]
    public void EpochChangeLeavesBothOldTopicsAndJoinsBothNewTopics()
    {
        var roomId = Guid.NewGuid();

        var delta = RealtimeEpochSubscriptionPlan.CreateDelta(
            new Dictionary<Guid, long> { [roomId] = 3 },
            new Dictionary<Guid, long> { [roomId] = 4 });

        Assert.Equal(2, delta.Leaves.Count);
        Assert.All(delta.Leaves, topic => Assert.Equal(3, topic.Epoch));
        Assert.Equal(2, delta.Joins.Count);
        Assert.All(delta.Joins, topic => Assert.Equal(4, topic.Epoch));
        Assert.Contains(delta.Joins, topic => topic.Kind == RealtimeTopicKind.Database);
        Assert.Contains(delta.Joins, topic => topic.Kind == RealtimeTopicKind.Ephemeral);
    }

    [Fact]
    public void PhoenixTopicRoundTripsExactRoomEpochAndKind()
    {
        var expected = new RealtimeRoomDescriptor(
            Guid.NewGuid(), 12, RealtimeTopicKind.Ephemeral);

        Assert.True(RealtimeRoomDescriptor.TryParsePhoenixTopic(
            expected.PhoenixTopic,
            out var parsed));
        Assert.Equal(expected, parsed);
        Assert.False(RealtimeRoomDescriptor.TryParsePhoenixTopic(
            $"realtime:room:{expected.RoomId:D}:11:unknown",
            out _));
    }

    [Fact]
    public void RejectsMoreThanFiveRoomsAndNonPositiveEpochs()
    {
        var tooMany = Enumerable.Range(0, 6)
            .ToDictionary(_ => Guid.NewGuid(), _ => 1L);

        Assert.Throws<ArgumentOutOfRangeException>(() =>
            RealtimeEpochSubscriptionPlan.CreateDelta(new Dictionary<Guid, long>(), tooMany));
        Assert.Throws<ArgumentException>(() =>
            RealtimeEpochSubscriptionPlan.CreateDelta(
                new Dictionary<Guid, long>(),
                new Dictionary<Guid, long> { [Guid.NewGuid()] = 0 }));
    }
}
