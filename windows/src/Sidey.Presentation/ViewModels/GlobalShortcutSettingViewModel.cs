using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Sidey.Presentation.Services;

namespace Sidey.Presentation.ViewModels;

/// <summary>
/// One settings row for a system-wide shortcut. The view reports a key combination
/// only while this row is recording; validation and saving stay in the view model.
/// </summary>
public sealed partial class GlobalShortcutSettingViewModel : ObservableObject
{
    private readonly IMainWindowCoordinator _coordinator;
    private readonly Action<GlobalShortcutSettingViewModel> _recordingStarted;
    private Func<string>? _message;

    internal GlobalShortcutSettingViewModel(
        GlobalShortcutAction shortcutAction,
        IMainWindowCoordinator coordinator,
        Action<GlobalShortcutSettingViewModel> recordingStarted)
    {
        ShortcutAction = shortcutAction;
        _coordinator = coordinator;
        _recordingStarted = recordingStarted;
    }

    public GlobalShortcutAction ShortcutAction { get; }

    [ObservableProperty]
    public partial string Title { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string ShortcutText { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string RecordTooltip { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string ClearText { get; set; } = string.Empty;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(ClearCommand))]
    public partial bool HasShortcut { get; set; }

    [ObservableProperty]
    public partial bool IsRecording { get; set; }

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(StartRecordingCommand))]
    [NotifyCanExecuteChangedFor(nameof(ClearCommand))]
    public partial bool IsSaving { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasStatus))]
    public partial string StatusText { get; set; } = string.Empty;

    public bool HasStatus => !string.IsNullOrEmpty(StatusText);

    internal static string TitleKey(GlobalShortcutAction action) => action switch
    {
        GlobalShortcutAction.Compose => "settings.shortcutCompose",
        GlobalShortcutAction.ToggleOverlay => "settings.shortcutToggleOverlay",
        GlobalShortcutAction.ToggleQuietMode => "settings.shortcutToggleQuietMode",
        _ => throw new ArgumentOutOfRangeException(nameof(action)),
    };

    internal void Apply(CoordinatorState state)
    {
        GlobalShortcut? shortcut = state.Preferences.GlobalShortcuts.Get(ShortcutAction);
        Title = I18n.Get(TitleKey(ShortcutAction));
        RecordTooltip = I18n.Get("settings.shortcutRecordTooltip");
        ClearText = I18n.Get("settings.shortcutClear");
        HasShortcut = shortcut is not null;
        ShortcutText = IsRecording
            ? I18n.Get("settings.shortcutRecording")
            : shortcut?.ToString() ?? I18n.Get("settings.shortcutNone");
        StatusText = _message?.Invoke()
            ?? RegistrationMessage(shortcut, state.GlobalShortcutStatuses.GetValueOrDefault(ShortcutAction));
    }

    [RelayCommand(CanExecute = nameof(CanStartRecording))]
    private void StartRecording()
    {
        _message = null;
        IsRecording = true;
        _recordingStarted(this);
        Apply(_coordinator.State);
    }

    private bool CanStartRecording() => !IsSaving;

    [RelayCommand]
    private void CancelRecording()
    {
        if (!IsRecording)
        {
            return;
        }

        IsRecording = false;
        Apply(_coordinator.State);
    }

    [RelayCommand]
    private Task RecordAsync(GlobalShortcut shortcut)
    {
        if (!IsRecording || IsSaving)
        {
            return Task.CompletedTask;
        }

        IsRecording = false;
        GlobalShortcutValidation validation = shortcut.Validate();
        if (validation != GlobalShortcutValidation.Valid)
        {
            string key = ValidationMessageKey(validation);
            ShowMessage(() => I18n.Get(key));
            return Task.CompletedTask;
        }

        if (_coordinator.State.Preferences.GlobalShortcuts.FindAction(shortcut) is { } owner
            && owner != ShortcutAction)
        {
            ShowMessage(() => I18n.Format("settings.shortcutDuplicate", I18n.Get(TitleKey(owner))));
            return Task.CompletedTask;
        }

        return ChangeAsync(shortcut);
    }

    [RelayCommand(CanExecute = nameof(CanClear))]
    private Task ClearAsync()
    {
        IsRecording = false;
        _message = null;
        return ChangeAsync(null);
    }

    private bool CanClear() => HasShortcut && !IsSaving;

    private async Task ChangeAsync(GlobalShortcut? shortcut)
    {
        IsSaving = true;
        try
        {
            GlobalShortcutRegistrationStatus status =
                await _coordinator.SetGlobalShortcutAsync(ShortcutAction, shortcut);
            _message = shortcut is not null && status != GlobalShortcutRegistrationStatus.Registered
                ? () => RegistrationMessage(shortcut, status)
                : null;
        }
        catch (Exception exception)
        {
            string message = exception.Message;
            _message = () => message;
        }
        finally
        {
            IsSaving = false;
            Apply(_coordinator.State);
        }
    }

    private void ShowMessage(Func<string> message)
    {
        _message = message;
        Apply(_coordinator.State);
    }

    private static string ValidationMessageKey(GlobalShortcutValidation validation) => validation switch
    {
        GlobalShortcutValidation.UsesWindowsKey => "settings.shortcutWindowsKey",
        GlobalShortcutValidation.UsesControlAlt => "settings.shortcutControlAlt",
        GlobalShortcutValidation.TooFewModifiers => "settings.shortcutTooFewModifiers",
        _ => "settings.shortcutUnsupportedKey",
    };

    private static string RegistrationMessage(
        GlobalShortcut? shortcut,
        GlobalShortcutRegistrationStatus status) => shortcut is null
            ? string.Empty
            : status switch
            {
                GlobalShortcutRegistrationStatus.InUse => I18n.Get("settings.shortcutInUse"),
                GlobalShortcutRegistrationStatus.Unavailable => I18n.Get("settings.shortcutUnavailable"),
                _ => string.Empty,
            };
}
