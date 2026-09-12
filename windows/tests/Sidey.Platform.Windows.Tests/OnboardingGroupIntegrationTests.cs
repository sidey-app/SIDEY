using System.Reflection;
using Sidey.App;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Core.Realtime;
using Sidey.Presentation.Services;
using Sidey.Presentation.ViewModels;

namespace Sidey.Platform.Windows.Tests;

public sealed class OnboardingGroupIntegrationTests
{
    [Theory]
    [InlineData(false, false)]
    [InlineData(false, true)]
    [InlineData(true, false)]
    [InlineData(true, true)]
    public async Task SuccessfulGroupSetupReachesReadyAndSelectsTheRoom(bool joining, bool existingRoom)
    {
        await using var coordinator = new AppCoordinator(new MemoryPreferences());
        IBackendGateway backend = DispatchProxy.Create<IBackendGateway, GroupBackend>();
        var server = (GroupBackend)backend;
        Room? previous = existingRoom ? server.NewRoom("Existing") : null;
        server.Rooms = previous is null ? [] : [previous];
        SetField(coordinator, "_backend", backend);
        SetField(coordinator, "_state", CoordinatorState.Initial with
        {
            Profile = server.Profile,
            Rooms = server.Rooms,
            ActiveRoomId = previous?.Id,
            Preferences = AppPreferences.Default with { OverlayVisible = false },
            RealtimeConnection = new RealtimeConnectionStatus(true, true, true),
        });
        var pipeline = new RoomSwitchPipeline(
            Bind<Func<Guid, CancellationToken, Task<IReadOnlyList<ChatMessage>>>>(coordinator, "PerformRoomSwitchAsync"),
            Bind<Func<Guid?, CancellationToken, Task>>(coordinator, "RestoreCommittedRoomAsync"),
            Bind<Action<Guid, IReadOnlyList<ChatMessage>>>(coordinator, "CommitRoomSwitch"),
            TimeSpan.Zero);
        pipeline.InitializeCommittedRoom(previous?.Id);
        RoomSessionLifetime session = Assert.IsType<RoomSessionLifetime>(typeof(AppCoordinator)
            .GetField("_roomSession", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(coordinator));
        session.SwitchPipeline = pipeline;
        using var onboarding = new OnboardingViewModel(coordinator)
        {
            Step = 2,
            RoomName = "Friends",
            InviteCode = "TEST",
        };
        var operations = new List<GroupOperation>();
        coordinator.StateChanged += state => operations.Add(state.GroupOperation);
        var syncing = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        server.Synchronize = () =>
        {
            syncing.TrySetResult();
            return release.Task;
        };

        Task request = joining
            ? onboarding.JoinRoomCommand.ExecuteAsync(null)
            : onboarding.CreateRoomCommand.ExecuteAsync(null);
        await syncing.Task.WaitAsync(TimeSpan.FromSeconds(5));
        try
        {
            Assert.Equal(joining ? GroupOperation.Joining : GroupOperation.Creating, coordinator.State.GroupOperation);
            await Assert.ThrowsAsync<InvalidOperationException>(() => coordinator.CreateRoomAsync("Duplicate"));
            await Assert.ThrowsAsync<InvalidOperationException>(() => coordinator.JoinRoomAsync("TEST"));
            await Assert.ThrowsAsync<InvalidOperationException>(() => coordinator.SwitchRoomAsync(server.Rooms.Last().Id));
            Assert.False(onboarding.CanCreateRoom);
            Assert.False(onboarding.CanJoinRoom);
        }
        finally
        {
            release.TrySetResult();
        }
        await request.WaitAsync(TimeSpan.FromSeconds(5));

        Assert.Null(onboarding.ErrorMessage);
        Assert.True(onboarding.IsReadyStep);
        Assert.Equal(1, server.Mutations);
        Assert.Equal(existingRoom ? 2 : 1, coordinator.State.Rooms.Count);
        Assert.Equal(server.Rooms.Last().Id, coordinator.State.ActiveRoomId);
        Assert.Equal(GroupOperation.Idle, coordinator.State.GroupOperation);
        Assert.DoesNotContain(GroupOperation.Idle, operations.SkipLast(1));
        Assert.False(coordinator.State.Preferences.OnboardingCompleted);
    }

    private static void SetField(AppCoordinator coordinator, string name, object value) =>
        typeof(AppCoordinator).GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(coordinator, value);

    private static T Bind<T>(AppCoordinator coordinator, string name) where T : Delegate =>
        typeof(AppCoordinator).GetMethod(name, BindingFlags.Instance | BindingFlags.NonPublic)!.CreateDelegate<T>(coordinator);

    private sealed class MemoryPreferences : IPreferencesStore
    {
        public ValueTask<AppPreferences> LoadAsync(CancellationToken cancellationToken = default) =>
            ValueTask.FromResult(AppPreferences.Default);
        public ValueTask SaveAsync(AppPreferences preferences, CancellationToken cancellationToken = default) =>
            ValueTask.CompletedTask;
    }

    public class GroupBackend : DispatchProxy
    {
        public Profile Profile { get; } = new(Guid.NewGuid(), "Friend", "pixel_cat");
        public IReadOnlyList<Room> Rooms { get; set; } = [];
        public int Mutations { get; private set; }
        public Func<Task> Synchronize { get; set; } = () => Task.CompletedTask;

        public Room NewRoom(string name) => new(Guid.NewGuid(), name, Profile.Id,
            [new RoomMember(Profile.Id, Profile.Nickname, Profile.CharacterId, PresenceState.Online)], "TEST", true, 1);

        protected override object? Invoke(MethodInfo? targetMethod, object?[]? args)
        {
            switch (targetMethod!.Name)
            {
                case nameof(IBackendGateway.CreateRoomAsync):
                case nameof(IBackendGateway.JoinRoomAsync):
                    Mutations++;
                    Room room = NewRoom("Friends");
                    Rooms = [.. Rooms, room];
                    return targetMethod.Name == nameof(IBackendGateway.CreateRoomAsync)
                        ? Task.FromResult(new CreateRoomResult(room, "TEST"))
                        : Task.FromResult(room);
                case nameof(IBackendGateway.FetchSnapshotAsync):
                    return Task.FromResult(new BackendSnapshot(Profile, Rooms, Profile.Id, new HashSet<string>()));
                case nameof(IBackendGateway.FetchRecentMessagesAsync):
                    return Task.FromResult<IReadOnlyList<ChatMessage>>([]);
                case nameof(IBackendGateway.SynchronizeRealtimeRoomsAsync):
                    return Synchronize();
                default:
                    throw new NotSupportedException(targetMethod.Name);
            }
        }
    }
}
