using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Sidey.Presentation.Services;

namespace Sidey.Presentation.ViewModels;

public sealed partial class OnboardingViewModel : ObservableObject
{
    private readonly ISideyCoordinator _coordinator;
    private CoordinatorState _state;
    private string _syncedProfileNickname = string.Empty;
    private string _syncedProfileCharacterId = PixelCharacterCatalog.FallbackId;

    public OnboardingViewModel(ISideyCoordinator coordinator, bool isPreviewMode = false)
    {
        _coordinator = coordinator ?? throw new ArgumentNullException(nameof(coordinator));
        IsPreviewMode = isPreviewMode;
        _state = coordinator.State;
        CharacterSelections = PixelCharacterCatalog.Selectable
            .Select(character => new CharacterSelectionItemViewModel(
                character.Id,
                character.DisplayName,
                character.Id))
            .ToArray();
        ApplyState(coordinator.State);
    }

    public event Action? Completed;

    public IReadOnlyList<CharacterSelectionItemViewModel> CharacterSelections { get; }

    public bool IsPreviewMode { get; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLanding))]
    [NotifyPropertyChangedFor(nameof(IsSetupVisible))]
    [NotifyPropertyChangedFor(nameof(IsProfileStep))]
    [NotifyPropertyChangedFor(nameof(IsGroupStep))]
    [NotifyPropertyChangedFor(nameof(IsReadyStep))]
    [NotifyPropertyChangedFor(nameof(CanGoBack))]
    public partial int Step { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanSaveProfile))]
    public partial string Nickname { get; set; } = string.Empty;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanSaveProfile))]
    public partial string SelectedCharacterId { get; set; } = PixelCharacterCatalog.FallbackId;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanCreateRoom))]
    public partial string RoomName { get; set; } = string.Empty;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanJoinRoom))]
    public partial string InviteCode { get; set; } = string.Empty;

    [ObservableProperty]
    public partial int GroupPathIndex { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanSaveProfile))]
    [NotifyPropertyChangedFor(nameof(CanCreateRoom))]
    [NotifyPropertyChangedFor(nameof(CanJoinRoom))]
    public partial bool IsConnected { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanSaveProfile))]
    [NotifyPropertyChangedFor(nameof(CanCreateRoom))]
    [NotifyPropertyChangedFor(nameof(CanJoinRoom))]
    public partial bool IsWorking { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasError))]
    public partial string? ErrorMessage { get; set; }

    public bool IsLanding => Step == 0;

    public bool IsSetupVisible => Step > 0;

    public bool IsProfileStep => Step == 1;

    public bool IsGroupStep => Step == 2;

    public bool IsReadyStep => Step == 3;

    public bool HasError => !string.IsNullOrWhiteSpace(ErrorMessage);

    public bool CanGoBack => Step is 1 or 2;

    public bool CanSaveProfile =>
        (IsPreviewMode || IsConnected)
        && !IsWorking
        && ProfileValidator.IsValidNickname(Nickname);

    public bool CanCreateRoom =>
        (IsPreviewMode || IsConnected)
        && !IsWorking
        && RoomNameValidator.IsValid(RoomName);

    public bool CanJoinRoom =>
        (IsPreviewMode || IsConnected)
        && !IsWorking
        && !string.IsNullOrWhiteSpace(InviteCode);

    public string ConnectionText => IsPreviewMode
        ? I18n.Get("onboarding.previewConnection")
        : IsConnected
        ? I18n.Get("onboarding.serverConnected")
        : I18n.Get("onboarding.serverConnecting");

    public void ApplyState(CoordinatorState state)
    {
        bool shouldApplyProfileDraft = ProfileDraftMatchesSyncedState();
        (string syncedNickname, string syncedCharacterId) = GetSyncedProfileDraft(state);
        _syncedProfileNickname = syncedNickname;
        _syncedProfileCharacterId = syncedCharacterId;

        _state = state;
        IsConnected = state.Connected;
        OnPropertyChanged(nameof(ConnectionText));

        if (shouldApplyProfileDraft)
        {
            Nickname = syncedNickname;
            SelectedCharacterId = syncedCharacterId;
        }

        if (IsPreviewMode && string.IsNullOrWhiteSpace(RoomName))
        {
            Room? previewRoom = state.ActiveRoomId is { } activeRoomId
                ? state.Rooms.FirstOrDefault(room => room.Id == activeRoomId)
                : null;
            previewRoom ??= state.Rooms.FirstOrDefault();
            if (previewRoom is not null)
            {
                RoomName = previewRoom.Name;
            }
        }

        UpdateCharacterSelectionState();

        if (!IsPreviewMode
            && Step > 0
            && state.Preferences.OnboardingCompleted
            && state.Rooms.Count > 0)
        {
            Step = 3;
        }
        else if (!IsPreviewMode && Step == 1 && state.Profile is not null)
        {
            Step = 2;
        }

        if (!string.IsNullOrWhiteSpace(state.ErrorMessage))
        {
            ErrorMessage = state.ErrorMessage;
        }

        RaiseActionAvailability();
    }

    public void ReportError(Exception exception) => ErrorMessage = exception.Message;

    [RelayCommand]
    private void Begin()
    {
        ErrorMessage = null;
        Step = IsPreviewMode
            ? 1
            : _state.Preferences.OnboardingCompleted && _state.Rooms.Count > 0
            ? 3
            : _state.Profile is null ? 1 : 2;
    }

    [RelayCommand]
    private void Back()
    {
        ErrorMessage = null;
        if (Step == 2)
        {
            Step = 1;
        }
        else if (Step == 1)
        {
            Step = 0;
        }
    }

    [RelayCommand]
    private async Task SaveProfileAsync()
    {
        if (!CanSaveProfile)
        {
            return;
        }

        if (IsPreviewMode)
        {
            Step = 2;
            return;
        }

        await RunAsync(async () =>
        {
            await _coordinator.SaveProfileAsync(Nickname, SelectedCharacterId);
            ApplyState(_coordinator.State);
            Step = 2;
        });
    }

    [RelayCommand]
    private async Task CreateRoomAsync()
    {
        if (!CanCreateRoom)
        {
            return;
        }

        if (IsPreviewMode)
        {
            Step = 3;
            return;
        }

        await RunAsync(async () =>
        {
            await _coordinator.CreateRoomAsync(RoomName);
            ApplyState(_coordinator.State);
        });
    }

    [RelayCommand]
    private async Task JoinRoomAsync()
    {
        if (!CanJoinRoom)
        {
            return;
        }

        if (IsPreviewMode)
        {
            Step = 3;
            return;
        }

        await RunAsync(async () =>
        {
            await _coordinator.JoinRoomAsync(InviteCode.Trim().ToUpperInvariant());
            ApplyState(_coordinator.State);
        });
    }

    [RelayCommand]
    private void Finish() => Completed?.Invoke();

    partial void OnSelectedCharacterIdChanged(string value) => UpdateCharacterSelectionState();

    partial void OnInviteCodeChanged(string value)
    {
        string normalized = value.ToUpperInvariant();
        if (!StringComparer.Ordinal.Equals(value, normalized))
        {
            InviteCode = normalized;
        }
    }

    private async Task RunAsync(Func<Task> action)
    {
        IsWorking = true;
        ErrorMessage = null;
        try
        {
            await action();
        }
        catch (Exception exception)
        {
            ErrorMessage = exception.Message;
        }
        finally
        {
            IsWorking = false;
        }
    }

    private void UpdateCharacterSelectionState()
    {
        foreach (CharacterSelectionItemViewModel character in CharacterSelections)
        {
            character.IsSelected = StringComparer.Ordinal.Equals(
                character.Id,
                SelectedCharacterId);
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

    private void RaiseActionAvailability()
    {
        OnPropertyChanged(nameof(CanSaveProfile));
        OnPropertyChanged(nameof(CanCreateRoom));
        OnPropertyChanged(nameof(CanJoinRoom));
    }
}
