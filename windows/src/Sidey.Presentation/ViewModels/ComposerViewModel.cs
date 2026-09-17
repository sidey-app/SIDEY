using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Sidey.Core.Domain;
using Sidey.Presentation.Services;

namespace Sidey.Presentation.ViewModels;

public enum ComposerAvailability
{
    Ready,
    WaitingForGroups,
    GroupRequired,
}

public sealed partial class ComposerViewModel : ObservableObject, IDisposable
{
    private DelayedAction? _autoClose;
    private string _draft = string.Empty;
    private ComposerAvailability _availability = ComposerAvailability.Ready;
    private bool _disposed;

    public string Draft
    {
        get => _draft;
        set
        {
            if (!MessageValidator.IsValidDraft(value))
            {
                OnPropertyChanged();
                return;
            }

            if (!SetProperty(ref _draft, value))
            {
                return;
            }

            SendCommand.NotifyCanExecuteChanged();
            CancelAutoClose();
            TypingChanged?.Invoke(!string.IsNullOrWhiteSpace(MessageValidator.Normalize(value)));
        }
    }

    public ComposerAvailability Availability
    {
        get => _availability;
        private set
        {
            if (!SetProperty(ref _availability, value))
            {
                return;
            }

            OnPropertyChanged(nameof(CanCompose));
            OnPropertyChanged(nameof(IsWaitingForGroups));
            OnPropertyChanged(nameof(IsGroupRequired));
            SendCommand.NotifyCanExecuteChanged();
            if (value != ComposerAvailability.Ready)
            {
                TypingChanged?.Invoke(false);
            }
        }
    }

    public bool CanCompose => Availability == ComposerAvailability.Ready;

    public bool IsWaitingForGroups => Availability == ComposerAvailability.WaitingForGroups;

    public bool IsGroupRequired => Availability == ComposerAvailability.GroupRequired;

    public event Action? CloseRequested;

    public event Action<string>? SendRequested;

    public event Action<bool>? TypingChanged;

    public event Action? GroupSettingsRequested;

    public bool CanAddLine =>
        Draft.Count(character => character == '\n') + 1 < MessageValidator.MaximumLines;

    public void OnShown() => CancelAutoClose();

    public void OnHidden()
    {
        CancelAutoClose();
        TypingChanged?.Invoke(false);
    }

    public void RestoreDraft(string body)
    {
        Draft = MessageValidator.IsValidDraft(body) ? body : string.Empty;
    }

    // A global shortcut can open the composer before a message can be sent, so the
    // composer explains why and keeps the draft instead of losing it on send.
    public void ApplyState(CoordinatorState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        Availability = state.ActiveRoomId is not null && state.Profile is not null
            ? ComposerAvailability.Ready
            : state.ContentLoading.Snapshot.HasValue && state.Rooms.Count == 0
                ? ComposerAvailability.GroupRequired
                : ComposerAvailability.WaitingForGroups;
    }

    [RelayCommand(CanExecute = nameof(CanSend))]
    private void Send()
    {
        if (!CanCompose)
        {
            return;
        }

        string body = MessageValidator.Normalize(Draft);
        if (!MessageValidator.IsValid(body))
        {
            SendCommand.NotifyCanExecuteChanged();
            return;
        }

        SendRequested?.Invoke(body);
        Draft = string.Empty;
        TypingChanged?.Invoke(false);
        ScheduleAutoClose();
    }

    [RelayCommand]
    private void Close() => CloseRequested?.Invoke();

    [RelayCommand]
    private void OpenGroupSettings() => GroupSettingsRequested?.Invoke();

    private bool CanSend() =>
        CanCompose && MessageValidator.IsValid(MessageValidator.Normalize(Draft));

    private void ScheduleAutoClose()
    {
        CancelAutoClose();
        _autoClose = DelayedAction.Start(
            TimeSpan.FromSeconds(5),
            () => CloseRequested?.Invoke());
    }

    private void CancelAutoClose()
    {
        _autoClose?.Cancel();
        _autoClose = null;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        CancelAutoClose();
    }
}
