using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Sidey.Presentation.Services;

namespace Sidey.Presentation.ViewModels;

public enum NoticeKind
{
    Informational,
    Success,
    Warning,
    Error,
}

public sealed record NoticeMessage(string Message, NoticeKind Kind);

public sealed partial class CharacterSelectionItemViewModel : ObservableObject
{
    public CharacterSelectionItemViewModel(string id, string displayName, string characterId)
    {
        Id = id;
        DisplayName = displayName;
        CharacterId = characterId;
    }

    public string Id { get; }

    public string DisplayName { get; }

    public string CharacterId { get; }

    [ObservableProperty]
    public partial bool IsSelected { get; set; }
}

public sealed record RoomMemberCardViewModel(
    Guid RoomId,
    Guid UserId,
    string Nickname,
    string CharacterId,
    bool IsOwner,
    bool IsCurrentUser,
    bool CanRemove,
    IAsyncRelayCommand RemoveCommand);

public sealed class RoomCardViewModel : ObservableObject
{
    private Room _room;
    private string _name = string.Empty;
    private string _details = string.Empty;
    private bool _isActive;
    private bool _canJoin;
    private bool _isOwner;
    private bool _isExpanded;
    private string _expansionGlyph = string.Empty;
    private string _expansionActionText = string.Empty;
    private string _inviteActionText = string.Empty;
    private bool _isInviteActionEnabled;
    private string _joinActionText = string.Empty;
    private bool _isJoinEnabled;
    private bool _isSwitching;
    private bool _areRoomActionsEnabled;
    private bool _areOwnerActionsEnabled;

    public RoomCardViewModel(
        Room room,
        IAsyncRelayCommand joinCommand,
        IRelayCommand toggleCommand,
        IAsyncRelayCommand inviteCommand,
        IAsyncRelayCommand leaveCommand,
        IAsyncRelayCommand renameCommand,
        IAsyncRelayCommand deleteCommand)
    {
        _room = room;
        JoinCommand = joinCommand;
        ToggleCommand = toggleCommand;
        InviteCommand = inviteCommand;
        LeaveCommand = leaveCommand;
        RenameCommand = renameCommand;
        DeleteCommand = deleteCommand;
    }

    public Room Room => _room;

    public string Name
    {
        get => _name;
        private set => SetProperty(ref _name, value);
    }

    public string Details
    {
        get => _details;
        private set => SetProperty(ref _details, value);
    }

    public bool IsActive
    {
        get => _isActive;
        private set => SetProperty(ref _isActive, value);
    }

    public bool CanJoin
    {
        get => _canJoin;
        private set => SetProperty(ref _canJoin, value);
    }

    public bool IsOwner
    {
        get => _isOwner;
        private set => SetProperty(ref _isOwner, value);
    }

    public bool IsExpanded
    {
        get => _isExpanded;
        private set => SetProperty(ref _isExpanded, value);
    }

    public string ExpansionGlyph
    {
        get => _expansionGlyph;
        private set => SetProperty(ref _expansionGlyph, value);
    }

    public string ExpansionActionText
    {
        get => _expansionActionText;
        private set => SetProperty(ref _expansionActionText, value);
    }

    public string InviteActionText
    {
        get => _inviteActionText;
        private set => SetProperty(ref _inviteActionText, value);
    }

    public bool IsInviteActionEnabled
    {
        get => _isInviteActionEnabled;
        private set => SetProperty(ref _isInviteActionEnabled, value);
    }

    public string JoinActionText
    {
        get => _joinActionText;
        private set => SetProperty(ref _joinActionText, value);
    }

    public bool IsJoinEnabled
    {
        get => _isJoinEnabled;
        private set => SetProperty(ref _isJoinEnabled, value);
    }

    public bool IsSwitching
    {
        get => _isSwitching;
        private set => SetProperty(ref _isSwitching, value);
    }

    public bool AreOwnerActionsEnabled
    {
        get => _areOwnerActionsEnabled;
        private set => SetProperty(ref _areOwnerActionsEnabled, value);
    }

    public bool AreRoomActionsEnabled
    {
        get => _areRoomActionsEnabled;
        private set => SetProperty(ref _areRoomActionsEnabled, value);
    }

    public ObservableCollection<RoomMemberCardViewModel> Members { get; } = [];

    public IAsyncRelayCommand JoinCommand { get; }

    public IRelayCommand ToggleCommand { get; }

    public IAsyncRelayCommand InviteCommand { get; }

    public IAsyncRelayCommand LeaveCommand { get; }

    public IAsyncRelayCommand RenameCommand { get; }

    public IAsyncRelayCommand DeleteCommand { get; }

    internal void Update(
        Room room,
        string details,
        bool isActive,
        bool isOwner,
        bool isExpanded,
        string joinActionText,
        bool isJoinEnabled,
        bool isSwitching,
        string inviteActionText,
        bool isInviteActionEnabled,
        bool areRoomActionsEnabled,
        bool areOwnerActionsEnabled,
        IReadOnlyList<RoomMemberCardViewModel> members)
    {
        _room = room;
        Name = room.Name;
        Details = details;
        IsActive = isActive;
        CanJoin = !isActive;
        IsOwner = isOwner;
        IsExpanded = isExpanded;
        JoinActionText = joinActionText;
        IsJoinEnabled = isJoinEnabled;
        IsSwitching = isSwitching;
        ExpansionGlyph = isExpanded ? "\uE70D" : "\uE76C";
        ExpansionActionText = isExpanded
            ? I18n.Get("groups.collapse")
            : I18n.Get("groups.expand");
        InviteActionText = inviteActionText;
        IsInviteActionEnabled = isInviteActionEnabled;
        AreRoomActionsEnabled = areRoomActionsEnabled;
        AreOwnerActionsEnabled = areOwnerActionsEnabled;
        UpdateMembers(members);
    }

    private void UpdateMembers(IReadOnlyList<RoomMemberCardViewModel> desiredMembers)
    {
        HashSet<Guid> desiredIds = desiredMembers.Select(member => member.UserId).ToHashSet();
        for (int index = Members.Count - 1; index >= 0; index--)
        {
            if (!desiredIds.Contains(Members[index].UserId))
            {
                Members.RemoveAt(index);
            }
        }

        for (int index = 0; index < desiredMembers.Count; index++)
        {
            RoomMemberCardViewModel desired = desiredMembers[index];
            int existingIndex = IndexOfMember(desired.UserId);
            if (existingIndex < 0)
            {
                Members.Insert(index, desired);
                continue;
            }

            if (existingIndex != index)
            {
                Members.Move(existingIndex, index);
            }

            if (!MemberPresentation(Members[index]).Equals(MemberPresentation(desired)))
            {
                Members[index] = desired;
            }
        }
    }

    private int IndexOfMember(Guid userId)
    {
        for (int index = 0; index < Members.Count; index++)
        {
            if (Members[index].UserId == userId)
            {
                return index;
            }
        }

        return -1;
    }

    private static (
        Guid RoomId,
        Guid UserId,
        string Nickname,
        string CharacterId,
        bool IsOwner,
        bool IsCurrentUser,
        bool CanRemove) MemberPresentation(RoomMemberCardViewModel member) =>
    (
        member.RoomId,
        member.UserId,
        member.Nickname,
        member.CharacterId,
        member.IsOwner,
        member.IsCurrentUser,
        member.CanRemove
    );
}

public sealed partial class MainWindowViewModel : ObservableObject
{
    private readonly ISideyCoordinator _coordinator;
    private readonly IMainWindowDialogService _dialogs;
    private readonly IUpdateService _updates;
    private readonly HashSet<Guid> _expandedRoomIds = [];
    private CoordinatorState _state = CoordinatorState.Initial;
    private CoordinatorState _previousState = CoordinatorState.Initial;
    private bool _isApplyingState;
    private bool _hasAppliedState;
    private bool _roomExpansionInitialized;
    private string _syncedProfileNickname = string.Empty;
    private string _syncedProfileCharacterId = PixelCharacterCatalog.FallbackId;

    [ObservableProperty]
    public partial string Nickname { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string SelectedCharacterId { get; set; } = PixelCharacterCatalog.FallbackId;

    [ObservableProperty]
    public partial string CreateRoomName { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string InviteCode { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string CreateRoomActionText { get; set; } = I18n.Get("groups.create");

    [ObservableProperty]
    public partial string JoinRoomActionText { get; set; } = I18n.Get("groups.joinByCode");

    [ObservableProperty]
    public partial bool AreGroupMutationsEnabled { get; set; } = true;

    [ObservableProperty]
    public partial bool IsConnected { get; set; }

    [ObservableProperty]
    public partial string ConnectionText { get; set; } = I18n.Get("connection.reconnecting");

    [ObservableProperty]
    public partial bool HasRooms { get; set; }

    [ObservableProperty]
    public partial bool IsOverlayVisible { get; set; }

    [ObservableProperty]
    public partial bool IsQuietMode { get; set; }

    [ObservableProperty]
    public partial bool ShowOfflineMembers { get; set; }

    [ObservableProperty]
    public partial bool RequiresRightClickToThrow { get; set; }

    [ObservableProperty]
    public partial bool StartAtLogin { get; set; }

    [ObservableProperty]
    public partial int SelectedEdgeIndex { get; set; }

    [ObservableProperty]
    public partial int SelectedSpanIndex { get; set; } = 2;

    [ObservableProperty]
    public partial string? SelectedMonitorIdentifier { get; set; }

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(CheckForUpdatesCommand))]
    public partial bool IsCheckingForUpdates { get; set; }

    [ObservableProperty]
    public partial string ValidationPathText { get; set; } = I18n.Get("metrics.rendererNotStarted");

    [ObservableProperty]
    public partial string ValidationMetricsText { get; set; } = I18n.Get("metrics.noSamples");

    public MainWindowViewModel(
        ISideyCoordinator coordinator,
        IMainWindowDialogService dialogs,
        IUpdateService updates)
    {
        _coordinator = coordinator ?? throw new ArgumentNullException(nameof(coordinator));
        _dialogs = dialogs ?? throw new ArgumentNullException(nameof(dialogs));
        _updates = updates ?? throw new ArgumentNullException(nameof(updates));
        CharacterSelections = PixelCharacterCatalog.Selectable
            .Select(character => new CharacterSelectionItemViewModel(
                character.Id,
                character.DisplayName,
                character.Id))
            .ToArray();
        Monitors = _coordinator.GetMonitors();
        ApplyState(coordinator.State);
        UpdateCharacterSelectionState();
    }

    public event Action<NoticeMessage>? NoticeRaised;

    public IReadOnlyList<CharacterSelectionItemViewModel> CharacterSelections { get; }

    public IReadOnlyList<MonitorOption> Monitors { get; }

    public ObservableCollection<RoomCardViewModel> Rooms { get; } = [];

    public bool IsValidationMode => _coordinator.IsValidationMode;

    public void PrepareGroupsForPresentation()
    {
        _expandedRoomIds.Clear();
        if (_state.ActiveRoomId is { } activeRoomId)
        {
            _expandedRoomIds.Add(activeRoomId);
            int activeRoomIndex = IndexOfRoom(activeRoomId);
            if (activeRoomIndex > 0)
            {
                Rooms.Move(activeRoomIndex, 0);
            }
        }

        RefreshRoomCards();
    }

    public void ApplyState(CoordinatorState state)
    {
        bool shouldApplyProfileDraft = ProfileDraftMatchesSyncedState();
        (string syncedNickname, string syncedCharacterId) = GetSyncedProfileDraft(state);
        _syncedProfileNickname = syncedNickname;
        _syncedProfileCharacterId = syncedCharacterId;

        _isApplyingState = true;
        try
        {
            _expandedRoomIds.IntersectWith(state.Rooms.Select(room => room.Id));
            if (!_roomExpansionInitialized || state.ActiveRoomId != _state.ActiveRoomId)
            {
                _expandedRoomIds.Clear();
                if (state.ActiveRoomId is { } activeRoomId)
                {
                    _expandedRoomIds.Add(activeRoomId);
                }

                _roomExpansionInitialized = true;
            }

            _state = state;
            if (shouldApplyProfileDraft)
            {
                Nickname = syncedNickname;
                SelectedCharacterId = syncedCharacterId;
            }

            RefreshRoomCards();
            HasRooms = state.Rooms.Count > 0;
            AreGroupMutationsEnabled = state.GroupOperation == GroupOperation.Idle;
            CreateRoomActionText = state.GroupOperation == GroupOperation.Creating
                ? I18n.Get("groups.creating")
                : I18n.Get("groups.create");
            JoinRoomActionText = state.GroupOperation == GroupOperation.Joining
                ? I18n.Get("groups.joining")
                : I18n.Get("groups.joinByCode");
            IsConnected = state.Connected;
            ConnectionText = state.Connected
                ? I18n.Get("connection.connected")
                : I18n.Get("connection.disconnected");
            IsOverlayVisible = state.Preferences.OverlayVisible;
            IsQuietMode = state.Preferences.QuietMode;
            ShowOfflineMembers = state.Preferences.ShowOfflineMembers;
            RequiresRightClickToThrow = state.Preferences.RequiresRightClickToThrow;
            StartAtLogin = state.Preferences.StartAtLogin;
            SelectedEdgeIndex = (int)state.Preferences.OverlayRegion.Edge;
            SelectedSpanIndex = (int)state.Preferences.OverlayRegion.Span;
            SelectedMonitorIdentifier = state.Preferences.OverlayRegion.MonitorIdentifier
                ?? Monitors.FirstOrDefault(monitor => monitor.IsPrimary)?.Identifier;
            RefreshValidationMetrics();
            RaiseConnectionNotice(state);
            _previousState = state;
            _hasAppliedState = true;
        }
        finally
        {
            _isApplyingState = false;
        }
    }

    public void ReportError(Exception exception) =>
        RaiseNotice(exception.Message, NoticeKind.Error);

    public void RefreshDiagnostics() => RefreshValidationMetrics();

    [RelayCommand]
    private async Task SaveProfileAsync() => await RunCommandAsync(
        () => _coordinator.SaveProfileAsync(Nickname, SelectedCharacterId),
        I18n.Get("profile.saved"));

    [RelayCommand]
    private async Task CreateRoomAsync() => await RunCommandAsync(
        () => _coordinator.CreateRoomAsync(CreateRoomName),
        I18n.Get("groups.createdSimple"));

    [RelayCommand]
    private async Task JoinRoomAsync() => await RunCommandAsync(
        () => _coordinator.JoinRoomAsync(InviteCode),
        I18n.Get("groups.joinedSimple"));

    [RelayCommand]
    private void Compose() => _coordinator.RequestComposer();

    [RelayCommand(CanExecute = nameof(CanCheckForUpdates))]
    private async Task CheckForUpdatesAsync()
    {
        IsCheckingForUpdates = true;
        try
        {
            AvailableUpdate? update = await _updates.CheckAsync();
            if (update is null)
            {
                RaiseNotice(I18n.Get("update.latest"), NoticeKind.Success);
                return;
            }

            if (!await _dialogs.ConfirmUpdateDownloadAsync(update.Version))
            {
                return;
            }

            RaiseNotice(I18n.Get("update.downloading"), NoticeKind.Informational);
            await _updates.DownloadAndLaunchInstallerAsync(update);
            RaiseNotice(
                I18n.Get("update.installerLaunched"),
                NoticeKind.Success);
        }
        catch (Exception exception)
        {
            RaiseNotice(I18n.Format("update.failed", exception.Message), NoticeKind.Error);
        }
        finally
        {
            IsCheckingForUpdates = false;
        }
    }

    public async Task CheckForUpdatesOnStartupAsync()
    {
        if (IsCheckingForUpdates)
        {
            return;
        }

        IsCheckingForUpdates = true;
        try
        {
            AvailableUpdate? update = await _updates.CheckAsync();
            if (update is not null)
            {
                RaiseNotice(
                    I18n.Format("update.startupAvailable", update.Version),
                    NoticeKind.Informational);
            }
        }
        finally
        {
            IsCheckingForUpdates = false;
        }
    }

    [RelayCommand]
    private async Task ExportValidationMetricsAsync()
    {
        try
        {
            string? path = await _coordinator.ExportValidationMetricsAsync();
            if (path is null)
            {
                RaiseNotice(I18n.Get("metrics.rendererNotRunning"), NoticeKind.Warning);
                return;
            }

            ValidationPathText = I18n.Format("metrics.exportPath", path);
            RaiseNotice(
                I18n.Get("metrics.exported"),
                NoticeKind.Success);
        }
        catch (Exception exception)
        {
            RaiseNotice(I18n.Format("metrics.exportFailed", exception.Message), NoticeKind.Error);
        }
    }

    partial void OnIsOverlayVisibleChanged(bool value)
    {
        if (!_isApplyingState)
        {
            _ = RunCommandAsync(() => _coordinator.SetOverlayVisibleAsync(value), null);
        }
    }

    partial void OnIsQuietModeChanged(bool value)
    {
        if (!_isApplyingState)
        {
            _ = RunCommandAsync(() => _coordinator.SetQuietModeAsync(value), null);
        }
    }

    partial void OnShowOfflineMembersChanged(bool value)
    {
        if (!_isApplyingState)
        {
            _ = RunCommandAsync(() => _coordinator.SetShowOfflineMembersAsync(value), null);
        }
    }

    partial void OnRequiresRightClickToThrowChanged(bool value)
    {
        if (!_isApplyingState)
        {
            _ = RunCommandAsync(() => _coordinator.SetRequiresRightClickToThrowAsync(value), null);
        }
    }

    partial void OnStartAtLoginChanged(bool value)
    {
        if (!_isApplyingState)
        {
            _ = RunCommandAsync(() => _coordinator.SetStartAtLoginAsync(value), null);
        }
    }

    partial void OnSelectedCharacterIdChanged(string value) => UpdateCharacterSelectionState();

    partial void OnSelectedEdgeIndexChanged(int value) => ApplyRegionPreference();

    partial void OnSelectedSpanIndexChanged(int value) => ApplyRegionPreference();

    partial void OnSelectedMonitorIdentifierChanged(string? value) => ApplyRegionPreference();

    private bool CanCheckForUpdates() => !IsCheckingForUpdates;

    private void UpdateCharacterSelectionState()
    {
        foreach (CharacterSelectionItemViewModel character in CharacterSelections)
        {
            character.IsSelected = StringComparer.Ordinal.Equals(character.Id, SelectedCharacterId);
        }
    }

    private bool ProfileDraftMatchesSyncedState() =>
        StringComparer.Ordinal.Equals(Nickname, _syncedProfileNickname)
        && StringComparer.Ordinal.Equals(SelectedCharacterId, _syncedProfileCharacterId);

    private static (string Nickname, string CharacterId) GetSyncedProfileDraft(
        CoordinatorState state) =>
    (
        state.Profile?.Nickname ?? state.Preferences.CachedNickname ?? string.Empty,
        PixelCharacterCatalog.NormalizeId(
            state.Profile?.CharacterId ?? state.Preferences.CachedCharacterId)
    );

    private void ApplyRegionPreference()
    {
        if (_isApplyingState
            || SelectedEdgeIndex < 0
            || SelectedSpanIndex < 0
            || string.IsNullOrWhiteSpace(SelectedMonitorIdentifier))
        {
            return;
        }

        var edge = (OverlayEdge)Math.Clamp(SelectedEdgeIndex, 0, 3);
        var span = (OverlaySpan)Math.Clamp(SelectedSpanIndex, 0, 2);
        _ = RunCommandAsync(
            () => _coordinator.SetRegionAsync(new OverlayRegionPreference(
                edge,
                span,
                SelectedMonitorIdentifier)),
            null);
    }

    private RoomCardViewModel CreateRoomCard(Room room)
    {
        var card = new RoomCardViewModel(
            room,
            new AsyncRelayCommand(() => SwitchRoomAsync(room.Id)),
            new RelayCommand(() => ToggleRoom(room.Id)),
            new AsyncRelayCommand(() => UseInviteCodeAsync(room.Id)),
            new AsyncRelayCommand(() => LeaveRoomAsync(room.Id)),
            new AsyncRelayCommand(() => RenameRoomAsync(room.Id)),
            new AsyncRelayCommand(() => DeleteRoomAsync(room.Id)));
        UpdateRoomCard(card, room);
        return card;
    }

    private void UpdateRoomCard(RoomCardViewModel card, Room room)
    {
        bool isActive = room.Id == _state.ActiveRoomId;
        bool isOwner = room.OwnerId == _state.Profile?.Id;
        bool isExpanded = _expandedRoomIds.Contains(room.Id);
        bool mutationsEnabled = _state.GroupOperation == GroupOperation.Idle;
        bool isSwitching = _state.GroupOperation == GroupOperation.Switching
            && _state.SwitchingRoomId == room.Id;
        RoomMemberCardViewModel[] members = room.Members.Select(member =>
            new RoomMemberCardViewModel(
                room.Id,
                member.UserId,
                member.Nickname,
                PixelCharacterCatalog.NormalizeId(member.CharacterId),
                member.UserId == room.OwnerId,
                member.UserId == _state.Profile?.Id,
                mutationsEnabled && isOwner && member.UserId != room.OwnerId,
                new AsyncRelayCommand(() => RemoveMemberAsync(room.Id, member.UserId))))
            .ToArray();
        card.Update(
            room,
            room.InviteCodeReady
                ? I18n.Format("groups.details", room.Members.Count, room.InviteCodeHint)
                : I18n.Format("groups.detailsRotationRequired", room.Members.Count),
            isActive,
            isOwner,
            isExpanded,
            isSwitching ? I18n.Get("groups.switching") : I18n.Get("groups.join"),
            !isActive
                && !isSwitching
                && (_state.GroupOperation is GroupOperation.Idle or GroupOperation.Switching),
            isSwitching,
            room.InviteCodeReady
                ? I18n.Get("groups.copyInvite")
                : I18n.Get("groups.rotateInvite"),
            mutationsEnabled && (room.InviteCodeReady || isOwner),
            mutationsEnabled,
            mutationsEnabled && isOwner,
            members);
    }

    private async Task SwitchRoomAsync(Guid roomId)
    {
        if (roomId == _state.ActiveRoomId)
        {
            return;
        }

        await RunCommandAsync(
            () => _coordinator.SwitchRoomAsync(roomId),
            I18n.Get("groups.switched"));
    }

    private void ToggleRoom(Guid roomId)
    {
        if (!_expandedRoomIds.Add(roomId))
        {
            _expandedRoomIds.Remove(roomId);
        }

        RefreshRoomCards();
    }

    private async Task UseInviteCodeAsync(Guid roomId)
    {
        if (RoomById(roomId) is not { } room)
        {
            return;
        }

        if (!room.InviteCodeReady && room.OwnerId == _state.Profile?.Id)
        {
            if (!await _dialogs.ConfirmInviteCodeRotationAsync())
            {
                return;
            }

            await RunCommandAsync(
                () => _coordinator.RotateInviteCodeAsync(room.Id),
                I18n.Get("groups.inviteRotated"));
            return;
        }

        await RunCommandAsync(async () =>
        {
            if (!await _coordinator.CopyInviteCodeAsync(room.Id))
            {
                throw new InvalidOperationException(I18n.Get("groups.inviteMissing"));
            }
        }, I18n.Get("groups.inviteCopied"));
    }

    private async Task RenameRoomAsync(Guid roomId)
    {
        if (RoomById(roomId) is not { } room)
        {
            return;
        }

        string? name = await _dialogs.PromptForRoomNameAsync(room.Name);
        if (name is null)
        {
            return;
        }

        await RunCommandAsync(
            () => _coordinator.RenameRoomAsync(room.Id, name),
            I18n.Get("groups.renamed"));
    }

    private async Task RemoveMemberAsync(Guid roomId, Guid userId)
    {
        RoomMember? member = RoomById(roomId)?.Members.FirstOrDefault(
            candidate => candidate.UserId == userId);
        if (member is null || !await _dialogs.ConfirmMemberRemovalAsync(member.Nickname))
        {
            return;
        }

        await RunCommandAsync(
            () => _coordinator.RemoveRoomMemberAsync(roomId, userId),
            I18n.Get("groups.memberRemoved"));
    }

    private async Task LeaveRoomAsync(Guid roomId)
    {
        if (RoomById(roomId) is not { } room)
        {
            return;
        }

        bool isOwner = room.OwnerId == _state.Profile?.Id;
        if (!await _dialogs.ConfirmRoomLeaveAsync(room.Name, isOwner))
        {
            return;
        }

        await RunCommandAsync(
            () => _coordinator.LeaveRoomAsync(room.Id),
            I18n.Get("groups.left"));
    }

    private async Task DeleteRoomAsync(Guid roomId)
    {
        if (RoomById(roomId) is not { } room)
        {
            return;
        }

        if (!await _dialogs.ConfirmRoomDeletionAsync(room.Name))
        {
            return;
        }

        await RunCommandAsync(
            () => _coordinator.DeleteRoomAsync(room.Id),
            I18n.Get("groups.deleted"));
    }

    private async Task RunCommandAsync(Func<Task> action, string? successMessage)
    {
        try
        {
            await action();
            if (!string.IsNullOrWhiteSpace(successMessage))
            {
                RaiseNotice(successMessage, NoticeKind.Success);
            }
        }
        catch (Exception exception)
        {
            RaiseNotice(exception.Message, NoticeKind.Error);
        }
    }

    private Room? ActiveRoom() => _state.ActiveRoomId is { } roomId
        ? _state.Rooms.FirstOrDefault(room => room.Id == roomId)
        : null;

    private void RaiseConnectionNotice(CoordinatorState state)
    {
        bool hasNewError = !string.IsNullOrWhiteSpace(state.ErrorMessage)
            && !StringComparer.Ordinal.Equals(state.ErrorMessage, _previousState.ErrorMessage);
        if (hasNewError)
        {
            RaiseNotice(state.ErrorMessage!, NoticeKind.Warning);
        }
        else if (_hasAppliedState && state.Connected && !_previousState.Connected)
        {
            RaiseNotice(I18n.Get("connection.serverConnected"), NoticeKind.Success);
        }
        else if (_hasAppliedState && !state.Connected && _previousState.Connected)
        {
            RaiseNotice(I18n.Get("connection.serverReconnecting"), NoticeKind.Informational);
        }
    }

    private void RaiseNotice(string message, NoticeKind kind) =>
        NoticeRaised?.Invoke(new NoticeMessage(message, kind));

    private void RefreshRoomCards()
    {
        HashSet<Guid> desiredIds = _state.Rooms.Select(room => room.Id).ToHashSet();
        for (int index = Rooms.Count - 1; index >= 0; index--)
        {
            if (!desiredIds.Contains(Rooms[index].Room.Id))
            {
                Rooms.RemoveAt(index);
            }
        }

        foreach (Room desired in _state.Rooms)
        {
            int existingIndex = IndexOfRoom(desired.Id);
            if (existingIndex < 0)
            {
                Rooms.Add(CreateRoomCard(desired));
                continue;
            }

            UpdateRoomCard(Rooms[existingIndex], desired);
        }
    }

    private int IndexOfRoom(Guid roomId)
    {
        for (int index = 0; index < Rooms.Count; index++)
        {
            if (Rooms[index].Room.Id == roomId)
            {
                return index;
            }
        }

        return -1;
    }

    private Room? RoomById(Guid roomId) =>
        _state.Rooms.FirstOrDefault(room => room.Id == roomId);

    private void RefreshValidationMetrics()
    {
        ValidationPathText = _coordinator.ValidationMetricsPath is { } path
            ? I18n.Format("metrics.exportPath", path)
            : I18n.Get("metrics.rendererNotStarted");
        ValidationMetricsSnapshot? summary = _coordinator.ValidationMetricsSummary;
        ValidationMetricsText = summary is null
            ? I18n.Get("metrics.noSamples")
            : I18n.Format(
                "metrics.summary",
                summary.ElapsedSeconds,
                summary.SampleCount,
                summary.MaximumFrameMilliseconds,
                summary.CurrentWorkingSetBytes / 1_048_576d,
                summary.PeakWorkingSetBytes / 1_048_576d,
                summary.MaximumGdiHandles,
                summary.MaximumUserHandles);
    }
}
