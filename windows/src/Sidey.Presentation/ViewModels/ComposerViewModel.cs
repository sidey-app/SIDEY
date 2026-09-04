using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Sidey.Core.Domain;
using Sidey.Presentation.Services;

namespace Sidey.Presentation.ViewModels;

public sealed partial class ComposerViewModel : ObservableObject, IDisposable
{
    private DelayedAction? _autoClose;
    private string _draft = string.Empty;
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

    public event Action? CloseRequested;

    public event Action<string>? SendRequested;

    public event Action<bool>? TypingChanged;

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

    [RelayCommand(CanExecute = nameof(CanSend))]
    private void Send()
    {
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

    private bool CanSend() => MessageValidator.IsValid(MessageValidator.Normalize(Draft));

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
