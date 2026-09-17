using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Sidey.Presentation.Services;
using Sidey.Presentation.ViewModels;

namespace Sidey.Presentation.Tests;

public sealed class GlobalShortcutSettingsTests
{
    private static readonly GlobalShortcut s_controlShiftM =
        new(GlobalShortcutModifiers.Control | GlobalShortcutModifiers.Shift, 0x4D);
    private static readonly GlobalShortcut s_altShiftM =
        new(GlobalShortcutModifiers.Alt | GlobalShortcutModifiers.Shift, 0x4D);

    [Fact]
    public void RowsFollowTheActionOrderAndStartUnassigned()
    {
        (_, MainWindowViewModel viewModel) = Create();

        Assert.Equal(
            [GlobalShortcutAction.Compose, GlobalShortcutAction.ToggleOverlay, GlobalShortcutAction.ToggleQuietMode],
            viewModel.GlobalShortcuts.Select(row => row.ShortcutAction));
        Assert.All(viewModel.GlobalShortcuts, row =>
        {
            Assert.False(row.HasShortcut);
            Assert.False(row.HasStatus);
            Assert.Equal(I18n.Get("settings.shortcutNone"), row.ShortcutText);
            Assert.False(row.ClearCommand.CanExecute(null));
        });
        Assert.Equal(I18n.Get("settings.shortcutCompose"), viewModel.GlobalShortcuts[0].Title);
    }

    [Fact]
    public async Task RecordingSavesAValidCombination()
    {
        (FakeSideyCoordinator coordinator, MainWindowViewModel viewModel) = Create();
        GlobalShortcutSettingViewModel row = viewModel.GlobalShortcuts[0];

        row.StartRecordingCommand.Execute(null);
        Assert.True(row.IsRecording);
        Assert.Equal(I18n.Get("settings.shortcutRecording"), row.ShortcutText);
        await row.RecordCommand.ExecuteAsync(s_controlShiftM);

        Assert.False(row.IsRecording);
        Assert.True(row.HasShortcut);
        Assert.False(row.HasStatus);
        Assert.Equal("Ctrl+Shift+M", row.ShortcutText);
        Assert.Equal([(GlobalShortcutAction.Compose, (GlobalShortcut?)s_controlShiftM)], coordinator.GlobalShortcutChanges);
        Assert.True(row.ClearCommand.CanExecute(null));
    }

    [Theory]
    [InlineData(GlobalShortcutModifiers.Control, 0x4D, "settings.shortcutTooFewModifiers")]
    [InlineData(GlobalShortcutModifiers.Control | GlobalShortcutModifiers.Alt, 0x4D, "settings.shortcutControlAlt")]
    [InlineData(GlobalShortcutModifiers.Windows | GlobalShortcutModifiers.Shift, 0x4D, "settings.shortcutWindowsKey")]
    [InlineData(GlobalShortcutModifiers.Control | GlobalShortcutModifiers.Shift, 0x7B, "settings.shortcutUnsupportedKey")]
    public async Task RejectedCombinationsExplainTheRuleWithoutSaving(
        GlobalShortcutModifiers modifiers,
        int keyCode,
        string messageKey)
    {
        (FakeSideyCoordinator coordinator, MainWindowViewModel viewModel) = Create();
        GlobalShortcutSettingViewModel row = viewModel.GlobalShortcuts[1];

        row.StartRecordingCommand.Execute(null);
        await row.RecordCommand.ExecuteAsync(new GlobalShortcut(modifiers, keyCode));

        Assert.False(row.IsRecording);
        Assert.Equal(I18n.Get(messageKey), row.StatusText);
        Assert.Empty(coordinator.GlobalShortcutChanges);

        row.StartRecordingCommand.Execute(null);
        Assert.False(row.HasStatus);
    }

    [Fact]
    public async Task RepeatedCombinationNamesTheActionThatUsesIt()
    {
        (FakeSideyCoordinator coordinator, MainWindowViewModel viewModel) = Create(
            GlobalShortcutPreferences.Empty.With(GlobalShortcutAction.Compose, s_controlShiftM));
        GlobalShortcutSettingViewModel overlay = viewModel.GlobalShortcuts[1];

        overlay.StartRecordingCommand.Execute(null);
        await overlay.RecordCommand.ExecuteAsync(s_controlShiftM);

        Assert.Equal(
            I18n.Format("settings.shortcutDuplicate", I18n.Get("settings.shortcutCompose")),
            overlay.StatusText);
        Assert.Empty(coordinator.GlobalShortcutChanges);
    }

    [Fact]
    public async Task ConflictWithAnotherProgramKeepsThePreviousCombination()
    {
        (FakeSideyCoordinator coordinator, MainWindowViewModel viewModel) = Create(
            GlobalShortcutPreferences.Empty.With(GlobalShortcutAction.Compose, s_controlShiftM));
        coordinator.GlobalShortcutRegistrationResult = GlobalShortcutRegistrationStatus.InUse;
        GlobalShortcutSettingViewModel row = viewModel.GlobalShortcuts[0];

        row.StartRecordingCommand.Execute(null);
        await row.RecordCommand.ExecuteAsync(s_altShiftM);

        Assert.Equal("Ctrl+Shift+M", row.ShortcutText);
        Assert.Equal(I18n.Get("settings.shortcutInUse"), row.StatusText);
    }

    [Fact]
    public void LaunchRegistrationFailureIsShownBesideTheSavedCombination()
    {
        var coordinator = new FakeSideyCoordinator();
        coordinator.State = coordinator.State with
        {
            Preferences = coordinator.State.Preferences with
            {
                GlobalShortcuts = GlobalShortcutPreferences.Empty.With(GlobalShortcutAction.ToggleQuietMode, s_altShiftM),
            },
            GlobalShortcutStatuses = new Dictionary<GlobalShortcutAction, GlobalShortcutRegistrationStatus>
            {
                [GlobalShortcutAction.ToggleQuietMode] = GlobalShortcutRegistrationStatus.InUse,
            },
        };

        var viewModel = new MainWindowViewModel(coordinator, new FakeMainWindowDialogService(), new FakeUpdateService());
        GlobalShortcutSettingViewModel row = viewModel.GlobalShortcuts[2];

        Assert.Equal("Alt+Shift+M", row.ShortcutText);
        Assert.Equal(I18n.Get("settings.shortcutInUse"), row.StatusText);
    }

    [Fact]
    public async Task ClearingRemovesTheCombination()
    {
        (FakeSideyCoordinator coordinator, MainWindowViewModel viewModel) = Create(
            GlobalShortcutPreferences.Empty.With(GlobalShortcutAction.ToggleOverlay, s_controlShiftM));
        GlobalShortcutSettingViewModel row = viewModel.GlobalShortcuts[1];

        await row.ClearCommand.ExecuteAsync(null);

        Assert.False(row.HasShortcut);
        Assert.Equal(I18n.Get("settings.shortcutNone"), row.ShortcutText);
        Assert.Equal([(GlobalShortcutAction.ToggleOverlay, (GlobalShortcut?)null)], coordinator.GlobalShortcutChanges);
    }

    [Fact]
    public void OnlyOneRowRecordsAtATimeAndDeactivationCancelsIt()
    {
        (_, MainWindowViewModel viewModel) = Create();

        viewModel.GlobalShortcuts[0].StartRecordingCommand.Execute(null);
        viewModel.GlobalShortcuts[2].StartRecordingCommand.Execute(null);

        Assert.Equal([false, false, true], viewModel.GlobalShortcuts.Select(row => row.IsRecording));
        viewModel.CancelGlobalShortcutRecording();
        Assert.All(viewModel.GlobalShortcuts, row => Assert.False(row.IsRecording));
        Assert.Equal(I18n.Get("settings.shortcutNone"), viewModel.GlobalShortcuts[2].ShortcutText);
    }

    [Fact]
    public void RegisteredCombinationPressedWhileRecordingIsTreatedAsTheRecordedInput()
    {
        (FakeSideyCoordinator coordinator, MainWindowViewModel viewModel) = Create(
            GlobalShortcutPreferences.Empty.With(GlobalShortcutAction.Compose, s_controlShiftM));
        GlobalShortcutSettingViewModel overlay = viewModel.GlobalShortcuts[1];

        Assert.False(viewModel.TryRecordRegisteredGlobalShortcut(GlobalShortcutAction.Compose));

        overlay.StartRecordingCommand.Execute(null);
        Assert.False(viewModel.TryRecordRegisteredGlobalShortcut(GlobalShortcutAction.ToggleQuietMode));
        Assert.True(viewModel.TryRecordRegisteredGlobalShortcut(GlobalShortcutAction.Compose));

        Assert.False(overlay.IsRecording);
        Assert.Equal(
            I18n.Format("settings.shortcutDuplicate", I18n.Get("settings.shortcutCompose")),
            overlay.StatusText);
        Assert.Empty(coordinator.GlobalShortcutChanges);
    }

    private static (FakeSideyCoordinator Coordinator, MainWindowViewModel ViewModel) Create(
        GlobalShortcutPreferences? shortcuts = null)
    {
        var coordinator = new FakeSideyCoordinator();
        coordinator.State = coordinator.State with
        {
            Preferences = coordinator.State.Preferences with
            {
                GlobalShortcuts = shortcuts ?? GlobalShortcutPreferences.Empty,
            },
        };
        var viewModel = new MainWindowViewModel(coordinator, new FakeMainWindowDialogService(), new FakeUpdateService());
        return (coordinator, viewModel);
    }
}
