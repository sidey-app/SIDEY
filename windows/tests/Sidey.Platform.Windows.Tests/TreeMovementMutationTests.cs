using System.Reflection;
using Sidey.App;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Core.Overlay;
using Sidey.Presentation.Services;

namespace Sidey.Platform.Windows.Tests;

public sealed class TreeMovementMutationTests
{
    [Fact]
    public async Task PendingMutationDoesNotOptimisticallyPauseOrSendADuplicate()
    {
        await using var fixture = new Fixture();
        var reply = new TaskCompletionSource<Profile>(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Server.Save = (_, _) => reply.Task;
        Task first = fixture.Coordinator.ToggleTreeMovementAsync(fixture.RoomId);
        await fixture.Coordinator.ToggleTreeMovementAsync(fixture.RoomId);
        Assert.Single(fixture.Server.Requests);
        Assert.False(fixture.Coordinator.State.Profile!.TreeMovementPaused);
        reply.SetResult(fixture.Profile with { TreeMovementPaused = true, TreeMovementRevision = 2 });
        await first;
        Assert.True(fixture.Coordinator.State.Profile!.TreeMovementPaused);
        Assert.All(fixture.Coordinator.State.Rooms.SelectMany(room => room.Members), member => Assert.True(member.TreeMovementPaused));
    }

    [Fact]
    public async Task FailedSaveKeepsTheConfirmedValueAndAllowsANewRequest()
    {
        await using var fixture = new Fixture();
        fixture.Server.Save = (_, _) => Task.FromException<Profile>(new IOException("offline"));
        await Assert.ThrowsAsync<IOException>(() => fixture.Coordinator.ToggleTreeMovementAsync(fixture.RoomId));
        Assert.False(fixture.Coordinator.State.Profile!.TreeMovementPaused);
        fixture.Server.Save = (_, _) => Task.FromResult(fixture.Profile with { TreeMovementPaused = true, TreeMovementRevision = 2 });
        await fixture.Coordinator.ToggleTreeMovementAsync(fixture.RoomId);
        Assert.Equal(2, fixture.Server.Requests.Count);
        Assert.True(fixture.Coordinator.State.Profile!.TreeMovementPaused);
    }

    [Fact]
    public async Task NewerSnapshotWinsOverAnOlderRpcAfterMovingRooms()
    {
        await using var fixture = new Fixture();
        var reply = new TaskCompletionSource<Profile>(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Server.Save = (_, _) => reply.Task;
        Task request = fixture.Coordinator.ToggleTreeMovementAsync(fixture.RoomId);
        var otherRoom = Guid.NewGuid();
        fixture.Apply(fixture.Profile with { TreeMovementRevision = 3 }, otherRoom);
        reply.SetResult(fixture.Profile with { TreeMovementPaused = true, TreeMovementRevision = 2 });
        await request;
        Assert.Equal(otherRoom, fixture.Coordinator.State.ActiveRoomId);
        Assert.False(fixture.Coordinator.State.Profile!.TreeMovementPaused);
        Assert.Equal(3, fixture.Coordinator.State.Profile!.TreeMovementRevision);
        Assert.All(fixture.Coordinator.State.Rooms.SelectMany(room => room.Members), member =>
        {
            Assert.False(member.TreeMovementPaused);
            Assert.Equal(3, member.TreeMovementRevision);
        });
        fixture.Apply(fixture.Profile with { TreeMovementPaused = true, TreeMovementRevision = 2 }, fixture.RoomId);
        Assert.False(fixture.Coordinator.State.Profile!.TreeMovementPaused);
    }

    [Fact]
    public async Task MigrationUsesZeroCasOnceAndAcceptsAnotherDevicesInitialization()
    {
        await using var fixture = new Fixture(revision: 0, legacyPaused: true);
        fixture.Server.Save = (_, _) => Task.FromResult(fixture.Profile with { TreeMovementRevision = 4 });
        await fixture.Migrate();
        await fixture.Migrate();
        Assert.Equal((true, 0L), Assert.Single(fixture.Server.Requests));
        Assert.False(fixture.Coordinator.State.Profile!.TreeMovementPaused);
        Assert.Equal(4, fixture.Coordinator.State.Profile!.TreeMovementRevision);
    }

    [Fact]
    public async Task FailedMigrationKeepsServerStateAndDoesNotRepeatOnRoomRefresh()
    {
        await using var fixture = new Fixture(revision: 0, legacyPaused: true);
        fixture.Server.Save = (_, _) => Task.FromException<Profile>(new IOException("offline"));
        await fixture.Migrate();
        fixture.Apply(fixture.Profile, Guid.NewGuid());
        await fixture.Migrate();
        Assert.Single(fixture.Server.Requests);
        Assert.False(fixture.Coordinator.State.Profile!.TreeMovementPaused);
        Assert.True(fixture.IsTreePaused);
    }

    [Fact]
    public async Task OldBackendPreservesLocalPauseAndPersistsRightClickWithoutRpc()
    {
        await using var fixture = new Fixture(revision: null, legacyPaused: true);
        Assert.True(fixture.IsTreePaused);
        await fixture.Coordinator.ToggleTreeMovementAsync(fixture.RoomId);
        Assert.False(fixture.IsTreePaused);
        Assert.False(fixture.Preferences.Saved.TreeMovementPaused);
        await fixture.Coordinator.ToggleTreeMovementAsync(fixture.RoomId);
        Assert.True(fixture.IsTreePaused);
        Assert.True(fixture.Preferences.Saved.TreeMovementPaused);
        Assert.Empty(fixture.Server.Requests);
    }

    [Fact]
    public async Task FirstClickUsesVisibleLegacyValueAndPreservesItUntilServerConfirms()
    {
        await using var fixture = new Fixture(revision: 0, legacyPaused: true);
        var reply = new TaskCompletionSource<Profile>(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Server.Save = (_, _) => reply.Task;
        Task request = fixture.Coordinator.ToggleTreeMovementAsync(fixture.RoomId);
        Assert.Equal((false, 0L), Assert.Single(fixture.Server.Requests));
        Assert.True(fixture.IsTreePaused);
        reply.SetResult(fixture.Profile with { TreeMovementRevision = 1 });
        await request;
        Assert.False(fixture.IsTreePaused);
    }

    [Fact]
    public async Task PendingMigrationPreservesTheVisibleLegacyPause()
    {
        await using var fixture = new Fixture(revision: 0, legacyPaused: true);
        var reply = new TaskCompletionSource<Profile>(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Server.Save = (_, _) => reply.Task;
        Task migration = fixture.Migrate();
        Assert.True(fixture.IsTreePaused);
        reply.SetResult(fixture.Profile with { TreeMovementPaused = true, TreeMovementRevision = 1 });
        await migration;
        Assert.True(fixture.IsTreePaused);
    }

    [Theory]
    [InlineData(null)]
    [InlineData(7L)]
    public async Task OldServerAndAlreadyInitializedProfilesNeverMigrate(long? revision)
    {
        await using var fixture = new Fixture(revision, legacyPaused: true);
        await fixture.Migrate();
        Assert.Empty(fixture.Server.Requests);
    }

    [Fact]
    public async Task SwitchingAccountsCancelsOldRequestWithoutReleasingTheNewAccountsGuard()
    {
        await using var fixture = new Fixture();
        var firstReply = new TaskCompletionSource<Profile>(TaskCreationOptions.RunContinuationsAsynchronously);
        var secondReply = new TaskCompletionSource<Profile>(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Server.Save = (_, _) => fixture.Server.Requests.Count == 1 ? firstReply.Task : secondReply.Task;
        Task first = fixture.Coordinator.ToggleTreeMovementAsync(fixture.RoomId);
        Profile secondProfile = fixture.Profile with { Id = Guid.NewGuid() };
        var secondRoom = Guid.NewGuid();
        fixture.Apply(secondProfile, secondRoom);
        Assert.True(fixture.Server.Tokens[0].IsCancellationRequested);
        Task second = fixture.Coordinator.ToggleTreeMovementAsync(secondRoom);
        Assert.Equal(2, fixture.Server.Requests.Count);
        firstReply.SetResult(fixture.Profile with { TreeMovementPaused = true, TreeMovementRevision = 2 });
        await first;
        await fixture.Coordinator.ToggleTreeMovementAsync(secondRoom);
        Assert.Equal(2, fixture.Server.Requests.Count);
        Assert.Equal(secondProfile.Id, fixture.Coordinator.State.Profile!.Id);
        Assert.False(fixture.IsTreePaused);
        secondReply.SetResult(secondProfile with { TreeMovementPaused = true, TreeMovementRevision = 2 });
        await second;
        Assert.True(fixture.IsTreePaused);
    }

    [Fact]
    public async Task SlowMigrationDoesNotDelayRealtimeSnapshotReconciliation()
    {
        await using var fixture = new Fixture(revision: 0, legacyPaused: true);
        var reply = new TaskCompletionSource<Profile>(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Server.Save = (_, _) => reply.Task;
        try
        {
            await fixture.Reconcile().WaitAsync(TimeSpan.FromSeconds(2));
            Assert.True(fixture.Server.Synchronized);
            Assert.Single(fixture.Server.Requests);
            Assert.True(fixture.IsTreePaused);
        }
        finally
        {
            reply.TrySetResult(fixture.Profile with { TreeMovementPaused = true, TreeMovementRevision = 1 });
            await fixture.Drain();
        }
    }

    private sealed class Fixture : IAsyncDisposable
    {
        public AppCoordinator Coordinator { get; }
        public MemoryPreferences Preferences { get; } = new();
        public bool IsTreePaused
        {
            get
            {
                WorldSnapshot world = Bind<Func<WorldSnapshot>>("CurrentWorldSnapshot")();
                return PixelMovementPolicy.IsTreePaused(world.Members.Single(member => member.IsCurrentUser), world.TreeMovementPaused);
            }
        }
        public Guid RoomId { get; } = Guid.NewGuid();
        public Profile Profile { get; }
        public TreeBackend Server { get; }

        public Fixture(long? revision = 1, bool legacyPaused = false)
        {
            Coordinator = new AppCoordinator(Preferences);
            Profile = new(Guid.NewGuid(), "Tree", "pixel_tree", TreeMovementRevision: revision);
            IBackendGateway backend = DispatchProxy.Create<IBackendGateway, TreeBackend>();
            Server = (TreeBackend)backend;
            SetField("_backend", backend);
            SetField("_state", CoordinatorState.Initial with
            {
                Preferences = AppPreferences.Default with { OverlayVisible = false, TreeMovementPaused = legacyPaused },
            });
            Apply(Profile, RoomId);
        }

        private static BackendSnapshot Snapshot(Profile profile, Guid roomId)
        {
            var room = new Room(roomId, "Friends", profile.Id,
                [new RoomMember(profile.Id, profile.Nickname, profile.CharacterId, PresenceState.Online,
                    TreeMovementPaused: profile.TreeMovementPaused, TreeMovementRevision: profile.TreeMovementRevision)],
                "TEST", true, 1);
            return new BackendSnapshot(profile, [room], profile.Id, new HashSet<string> { "character:pixel_tree" });
        }

        public void Apply(Profile profile, Guid roomId) => Bind<Action<BackendSnapshot>>("ApplySnapshot")(Snapshot(profile, roomId));
        public Task Reconcile() => Bind<Func<BackendSnapshot, CancellationToken, Task>>("ReconcileSnapshotAsync")(
            Snapshot(Profile, RoomId), CancellationToken.None);
        public Task Drain() => Task.WhenAll((List<Task>)typeof(AppCoordinator)
            .GetField("_treeMovementOperations", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(Coordinator)!);
        public Task Migrate() => Bind<Func<CancellationToken, Task>>("MigrateTreeMovementAsync")(CancellationToken.None);
        private void SetField(string name, object value) => typeof(AppCoordinator)
            .GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(Coordinator, value);
        private T Bind<T>(string name) where T : Delegate => typeof(AppCoordinator)
            .GetMethod(name, BindingFlags.Instance | BindingFlags.NonPublic)!.CreateDelegate<T>(Coordinator);
        public ValueTask DisposeAsync() => Coordinator.DisposeAsync();
    }

    public class TreeBackend : DispatchProxy
    {
        public List<(bool Paused, long Revision)> Requests { get; } = [];
        public List<CancellationToken> Tokens { get; } = [];
        public bool Synchronized { get; private set; }
        public Func<bool, long, Task<Profile>> Save { get; set; } = (_, _) => throw new InvalidOperationException("Unexpected save");
        protected override object? Invoke(MethodInfo? targetMethod, object?[]? args)
        {
            if (targetMethod!.Name == nameof(IBackendGateway.SynchronizeRealtimeRoomsAsync))
            {
                Synchronized = true;
                return Task.CompletedTask;
            }
            if (targetMethod.Name != nameof(IBackendGateway.SetTreeMovementPausedAsync))
                throw new NotSupportedException(targetMethod.Name);
            bool paused = (bool)args![0]!;
            long revision = (long)args[1]!;
            Requests.Add((paused, revision));
            Tokens.Add((CancellationToken)args[2]!);
            return Save(paused, revision);
        }
    }

    private sealed class MemoryPreferences : IPreferencesStore
    {
        public AppPreferences Saved { get; private set; } = AppPreferences.Default;
        public ValueTask<AppPreferences> LoadAsync(CancellationToken cancellationToken = default) => ValueTask.FromResult(Saved);
        public ValueTask SaveAsync(AppPreferences preferences, CancellationToken cancellationToken = default)
        {
            Saved = preferences;
            return ValueTask.CompletedTask;
        }
    }
}
