using Sidey.Core.Domain;
using Sidey.Presentation.Services;
using Sidey.Presentation.ViewModels;

namespace Sidey.Platform.Windows.Tests;

public sealed class MainWindowViewModelTests
{
    [Fact]
    public void CharacterPickerKeepsTheFiveFreeWindowsSelections()
    {
        (FakeSideyCoordinator coordinator, _) = CreateRoomState();
        var viewModel = new MainWindowViewModel(
            coordinator,
            new FakeMainWindowDialogService(),
            new FakeUpdateService());

        Assert.Equal(
            ["pixel_hamster", "pixel_cat", "pixel_puppy", "pixel_rabbit", "pixel_penguin"],
            viewModel.CharacterSelections.Select(character => character.Id));
    }

    [Fact]
    public void ApplyingEquivalentSnapshotPreservesRoomItemIdentity()
    {
        (FakeSideyCoordinator coordinator, CoordinatorState state) = CreateRoomState();
        var viewModel = new MainWindowViewModel(
            coordinator,
            new FakeMainWindowDialogService(),
            new FakeUpdateService());
        RoomCardViewModel firstCard = Assert.Single(viewModel.Rooms);

        viewModel.ApplyState(state with { Connected = true });

        Assert.Same(firstCard, Assert.Single(viewModel.Rooms));
        Assert.True(viewModel.IsConnected);
        Assert.Equal("연결됨", viewModel.ConnectionText);
    }

    [Fact]
    public void RoomProjectionMarksCurrentUserAndOwnerWithoutUiTypes()
    {
        (FakeSideyCoordinator coordinator, _) = CreateRoomState();
        var viewModel = new MainWindowViewModel(
            coordinator,
            new FakeMainWindowDialogService(),
            new FakeUpdateService());

        RoomMemberCardViewModel member = Assert.Single(Assert.Single(viewModel.Rooms).Members);

        Assert.True(member.IsCurrentUser);
        Assert.True(member.IsOwner);
        Assert.False(member.CanRemove);
        Assert.Equal("pixel_hamster", member.CharacterId);
    }

    [Fact]
    public void CharacterSelectionItemsTrackTheSelectedCharacter()
    {
        (FakeSideyCoordinator coordinator, _) = CreateRoomState();
        var viewModel = new MainWindowViewModel(
            coordinator,
            new FakeMainWindowDialogService(),
            new FakeUpdateService());
        CharacterSelectionItemViewModel initial = Assert.Single(viewModel.CharacterSelections, character => character.IsSelected);
        CharacterSelectionItemViewModel next = viewModel.CharacterSelections
            .First(character => !character.IsSelected);

        Assert.Equal("pixel_hamster", initial.Id);

        viewModel.SelectedCharacterId = next.Id;

        Assert.True(next.IsSelected);
        Assert.False(initial.IsSelected);
        Assert.Single(viewModel.CharacterSelections, character => character.IsSelected);
    }

    [Fact]
    public void RealtimeStateUpdatePreservesUnsavedProfileDraft()
    {
        (FakeSideyCoordinator coordinator, CoordinatorState state) = CreateRoomState();
        var viewModel = new MainWindowViewModel(
            coordinator,
            new FakeMainWindowDialogService(),
            new FakeUpdateService())
        {
            Nickname = "draft-name",
            SelectedCharacterId = "pixel_cat",
        };

        viewModel.ApplyState(state with { Connected = true });

        Assert.Equal("draft-name", viewModel.Nickname);
        Assert.Equal("pixel_cat", viewModel.SelectedCharacterId);
        Assert.True(viewModel.CharacterSelections.Single(item => item.Id == "pixel_cat").IsSelected);
    }

    [Fact]
    public void ServerProfileChangeUpdatesAnUneditedProfileDraft()
    {
        (FakeSideyCoordinator coordinator, CoordinatorState state) = CreateRoomState();
        var viewModel = new MainWindowViewModel(
            coordinator,
            new FakeMainWindowDialogService(),
            new FakeUpdateService());
        Profile changedProfile = state.Profile! with
        {
            Nickname = "server-name",
            CharacterId = "pixel_penguin",
        };

        viewModel.ApplyState(state with { Profile = changedProfile });

        Assert.Equal("server-name", viewModel.Nickname);
        Assert.Equal("pixel_penguin", viewModel.SelectedCharacterId);
    }

    [Fact]
    public void CachedProfileSeedsTheFirstFrameBeforeTheServerProfileArrives()
    {
        var preferences = AppPreferences.CreateDefault() with
        {
            CachedNickname = "캐시 이름",
            CachedCharacterId = "pixel_penguin",
        };
        var coordinator = new FakeSideyCoordinator
        {
            State = CoordinatorState.Initial with { Preferences = preferences },
        };

        var viewModel = new MainWindowViewModel(
            coordinator,
            new FakeMainWindowDialogService(),
            new FakeUpdateService());

        Assert.Equal("캐시 이름", viewModel.Nickname);
        Assert.Equal("pixel_penguin", viewModel.SelectedCharacterId);
        Assert.True(viewModel.CharacterSelections.Single(item => item.Id == "pixel_penguin").IsSelected);
    }

    [Fact]
    public void RealtimeRoomChangesUpdateExistingCardInsteadOfReplacingIt()
    {
        (FakeSideyCoordinator coordinator, CoordinatorState state) = CreateRoomState();
        var viewModel = new MainWindowViewModel(
            coordinator,
            new FakeMainWindowDialogService(),
            new FakeUpdateService());
        RoomCardViewModel card = Assert.Single(viewModel.Rooms);
        Room changedRoom = state.Rooms[0] with
        {
            Name = "부드러운 그룹",
            Members =
            [
                state.Rooms[0].Members[0] with { Nickname = "새 닉네임" },
                new RoomMember(Guid.NewGuid(), "친구", "pixel_cat", PresenceState.Online),
            ],
        };

        viewModel.ApplyState(state with { Rooms = [changedRoom] });

        Assert.Same(card, Assert.Single(viewModel.Rooms));
        Assert.Equal("부드러운 그룹", card.Name);
        Assert.Equal(2, card.Members.Count);
        Assert.Equal("새 닉네임", card.Members[0].Nickname);
    }

    [Fact]
    public void ChangingActiveRoomKeepsCurrentOrderAndClosesInactiveRooms()
    {
        (FakeSideyCoordinator coordinator, CoordinatorState state) = CreateMultiRoomState();
        var viewModel = new MainWindowViewModel(
            coordinator,
            new FakeMainWindowDialogService(),
            new FakeUpdateService());
        RoomCardViewModel firstRoom = viewModel.Rooms[0];
        RoomCardViewModel secondRoom = viewModel.Rooms[1];
        secondRoom.ToggleCommand.Execute(null);

        viewModel.ApplyState(state with { ActiveRoomId = secondRoom.Room.Id });

        Assert.Same(firstRoom, viewModel.Rooms[0]);
        Assert.Same(secondRoom, viewModel.Rooms[1]);
        Assert.False(firstRoom.IsExpanded);
        Assert.True(secondRoom.IsExpanded);
    }

    [Fact]
    public void PreparingGroupsMovesActiveRoomFirstAndRestoresDefaultExpansion()
    {
        (FakeSideyCoordinator coordinator, CoordinatorState state) = CreateMultiRoomState();
        var viewModel = new MainWindowViewModel(
            coordinator,
            new FakeMainWindowDialogService(),
            new FakeUpdateService());
        RoomCardViewModel firstRoom = viewModel.Rooms[0];
        RoomCardViewModel secondRoom = viewModel.Rooms[1];

        viewModel.ApplyState(state with { ActiveRoomId = secondRoom.Room.Id });
        firstRoom.ToggleCommand.Execute(null);
        viewModel.PrepareGroupsForPresentation();

        Assert.Same(secondRoom, viewModel.Rooms[0]);
        Assert.Same(firstRoom, viewModel.Rooms[1]);
        Assert.True(secondRoom.IsExpanded);
        Assert.False(firstRoom.IsExpanded);
    }

    [Fact]
    public async Task StartupUpdateCheckOnlyNotifiesWhenAnUpdateExists()
    {
        (FakeSideyCoordinator coordinator, _) = CreateRoomState();
        var updates = new FakeUpdateService
        {
            AvailableUpdate = new AvailableUpdate("0.3.0-alpha.3"),
        };
        var viewModel = new MainWindowViewModel(
            coordinator,
            new FakeMainWindowDialogService(),
            updates);
        NoticeMessage? notice = null;
        viewModel.NoticeRaised += value => notice = value;

        await viewModel.CheckForUpdatesOnStartupAsync();

        Assert.NotNull(notice);
        Assert.Equal(NoticeKind.Informational, notice.Kind);
        Assert.Contains("0.3.0-alpha.3", notice.Message, StringComparison.Ordinal);
        Assert.Equal(0, updates.InstallerLaunchCount);
    }

    [Fact]
    public async Task StartupUpdateCheckIsSilentWhenCurrentVersionIsLatest()
    {
        (FakeSideyCoordinator coordinator, _) = CreateRoomState();
        var viewModel = new MainWindowViewModel(
            coordinator,
            new FakeMainWindowDialogService(),
            new FakeUpdateService());
        var noticeCount = 0;
        viewModel.NoticeRaised += _ => noticeCount++;

        await viewModel.CheckForUpdatesOnStartupAsync();

        Assert.Equal(0, noticeCount);
    }

    [Fact]
    public async Task ManualUpdateCheckReportsTheLatestVersion()
    {
        (FakeSideyCoordinator coordinator, _) = CreateRoomState();
        var viewModel = new MainWindowViewModel(
            coordinator,
            new FakeMainWindowDialogService(),
            new FakeUpdateService());
        NoticeMessage? notice = null;
        viewModel.NoticeRaised += value => notice = value;

        await viewModel.CheckForUpdatesCommand.ExecuteAsync(null);

        Assert.Equal("최신 버전을 사용하고 있습니다.", notice?.Message);
        Assert.Equal(NoticeKind.Success, notice?.Kind);
    }

    [Fact]
    public async Task ManualUpdateCheckDownloadsOnlyAfterConfirmation()
    {
        (FakeSideyCoordinator coordinator, _) = CreateRoomState();
        var dialogs = new FakeMainWindowDialogService();
        var updates = new FakeUpdateService
        {
            AvailableUpdate = new AvailableUpdate("0.3.0-alpha.3"),
        };
        var viewModel = new MainWindowViewModel(coordinator, dialogs, updates);

        await viewModel.CheckForUpdatesCommand.ExecuteAsync(null);

        Assert.Equal(1, updates.InstallerLaunchCount);
    }

    [Fact]
    public async Task ManualUpdateCheckDoesNotDownloadWhenDeclined()
    {
        (FakeSideyCoordinator coordinator, _) = CreateRoomState();
        var dialogs = new FakeMainWindowDialogService { ConfirmUpdateDownload = false };
        var updates = new FakeUpdateService
        {
            AvailableUpdate = new AvailableUpdate("0.3.0-alpha.3"),
        };
        var viewModel = new MainWindowViewModel(coordinator, dialogs, updates);

        await viewModel.CheckForUpdatesCommand.ExecuteAsync(null);

        Assert.Equal(0, updates.InstallerLaunchCount);
    }

    [Fact]
    public void SwitchingStateIdentifiesTheTargetAndDisablesMutations()
    {
        (FakeSideyCoordinator coordinator, CoordinatorState state) = CreateMultiRoomState();
        var viewModel = new MainWindowViewModel(
            coordinator,
            new FakeMainWindowDialogService(),
            new FakeUpdateService());
        Guid targetRoomId = state.Rooms[1].Id;

        viewModel.ApplyState(state with
        {
            GroupOperation = GroupOperation.Switching,
            SwitchingRoomId = targetRoomId,
        });

        RoomCardViewModel target = viewModel.Rooms.Single(room => room.Room.Id == targetRoomId);
        RoomCardViewModel active = viewModel.Rooms.Single(room => room.Room.Id == state.ActiveRoomId);
        Assert.True(target.IsSwitching);
        Assert.Equal("연결 중…", target.JoinActionText);
        Assert.False(target.IsJoinEnabled);
        Assert.False(active.IsSwitching);
        Assert.False(viewModel.AreGroupMutationsEnabled);
        Assert.All(viewModel.Rooms, room => Assert.False(room.AreRoomActionsEnabled));
        Assert.All(viewModel.Rooms, room => Assert.False(room.AreOwnerActionsEnabled));
        Assert.All(viewModel.Rooms.SelectMany(room => room.Members), member =>
            Assert.False(member.CanRemove));
    }

    [Theory]
    [InlineData(GroupOperation.Creating, "만드는 중…", "코드로 참여")]
    [InlineData(GroupOperation.Joining, "그룹 만들기", "참여 중…")]
    [InlineData(GroupOperation.Mutating, "그룹 만들기", "코드로 참여")]
    public void CreateAndJoinOperationsExposeProgressCopy(
        GroupOperation operation,
        string createText,
        string joinText)
    {
        (FakeSideyCoordinator coordinator, CoordinatorState state) = CreateRoomState();
        var viewModel = new MainWindowViewModel(
            coordinator,
            new FakeMainWindowDialogService(),
            new FakeUpdateService());

        viewModel.ApplyState(state with { GroupOperation = operation });

        Assert.Equal(createText, viewModel.CreateRoomActionText);
        Assert.Equal(joinText, viewModel.JoinRoomActionText);
        Assert.False(viewModel.AreGroupMutationsEnabled);
    }

    [Fact]
    public async Task MemberRemovalRequiresNamedConfirmationAndUsesGlobalInAppNotice()
    {
        (FakeSideyCoordinator coordinator, CoordinatorState state) = CreateRoomState();
        Guid friendId = Guid.NewGuid();
        Room room = state.Rooms[0] with
        {
            Members =
            [
                .. state.Rooms[0].Members,
                new RoomMember(friendId, "친구별", "pixel_cat", PresenceState.Online),
            ],
        };
        state = state with { Rooms = [room] };
        coordinator.State = state;
        var dialogs = new FakeMainWindowDialogService { ConfirmMemberRemoval = false };
        var viewModel = new MainWindowViewModel(coordinator, dialogs, new FakeUpdateService());
        RoomMemberCardViewModel member = Assert.Single(
            Assert.Single(viewModel.Rooms).Members,
            candidate => candidate.UserId == friendId);

        await member.RemoveCommand.ExecuteAsync(null);
        Assert.Equal("친구별", dialogs.ConfirmedRemovalNickname);
        Assert.Equal(0, coordinator.RemoveRoomMemberCallCount);

        dialogs.ConfirmMemberRemoval = true;
        NoticeMessage? notice = null;
        viewModel.NoticeRaised += value => notice = value;
        await member.RemoveCommand.ExecuteAsync(null);

        Assert.Equal(1, coordinator.RemoveRoomMemberCallCount);
        Assert.Equal(NoticeKind.Success, notice?.Kind);
        Assert.Equal("멤버를 내보냈습니다.", notice?.Message);
    }

    [Fact]
    public async Task LeavingAnyRoomRequiresConfirmationAndUsesTheSelectedRoom()
    {
        (FakeSideyCoordinator coordinator, _) = CreateMultiRoomState();
        var dialogs = new FakeMainWindowDialogService { ConfirmRoomLeave = false };
        var viewModel = new MainWindowViewModel(coordinator, dialogs, new FakeUpdateService());
        RoomCardViewModel room = viewModel.Rooms[1];

        await room.LeaveCommand.ExecuteAsync(null);

        Assert.Equal("Second", dialogs.ConfirmedLeaveRoomName);
        Assert.True(dialogs.ConfirmedLeaveRoomIsOwner);
        Assert.Equal(0, coordinator.LeaveRoomCallCount);

        dialogs.ConfirmRoomLeave = true;
        NoticeMessage? notice = null;
        viewModel.NoticeRaised += value => notice = value;
        await room.LeaveCommand.ExecuteAsync(null);

        Assert.Equal(1, coordinator.LeaveRoomCallCount);
        Assert.Equal(room.Room.Id, coordinator.LastLeftRoomId);
        Assert.Equal(NoticeKind.Success, notice?.Kind);
        Assert.Equal("그룹에서 나왔습니다.", notice?.Message);
    }

    private static (FakeSideyCoordinator Coordinator, CoordinatorState State) CreateRoomState()
    {
        Guid userId = Guid.NewGuid();
        Guid roomId = Guid.NewGuid();
        var profile = new Profile(userId, "aryu", "pixel_hamster");
        var room = new Room(
            roomId,
            "Test",
            userId,
            [new RoomMember(userId, profile.Nickname, profile.CharacterId, PresenceState.Online)],
            "••••-TEST",
            true,
            1);
        CoordinatorState state = CoordinatorState.Initial with
        {
            Profile = profile,
            Rooms = [room],
            ActiveRoomId = roomId,
            Connected = false,
        };
        return (new FakeSideyCoordinator { State = state }, state);
    }

    private static (FakeSideyCoordinator Coordinator, CoordinatorState State) CreateMultiRoomState()
    {
        (FakeSideyCoordinator coordinator, CoordinatorState state) = CreateRoomState();
        Guid secondRoomId = Guid.NewGuid();
        Room secondRoom = state.Rooms[0] with
        {
            Id = secondRoomId,
            Name = "Second",
            InviteCodeHint = "••••-NEXT",
        };
        CoordinatorState multiRoomState = state with { Rooms = [state.Rooms[0], secondRoom] };
        coordinator.State = multiRoomState;
        return (coordinator, multiRoomState);
    }
}
