using Microsoft.UI.Xaml;
using Sidey.Platform.Windows;

namespace Sidey.App;

public partial class App : Application
{
    private Window? _window;
    private MainWindow? _mainWindow;
    private ComposerWindow? _composer;
    private AppCoordinator? _coordinator;
    private SingleInstanceGuard? _singleInstance;
    private TrayIconService? _tray;
    private bool _shuttingDown;

    public App()
    {
        InitializeComponent();
    }

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        _ = args;
        _singleInstance = SingleInstanceGuard.Acquire();
        if (!_singleInstance.IsPrimary)
        {
            Exit();
            return;
        }

        if (!WindowsVersionGuard.IsSupported())
        {
            _window = new UnsupportedWindowsWindow();
            _window.Closed += OnWindowClosed;
            _window.Activate();
            return;
        }

        _coordinator = new AppCoordinator();
        _coordinator.ComposerRequested += RequestComposer;
        _coordinator.PulseRequested += RequestPulse;
        _coordinator.SendFailed += RestoreFailedDraft;
        _coordinator.RenderingFailed += OnRenderingFailed;
        _coordinator.GroupSetupRequested += OnGroupSetupRequested;
        _coordinator.StateChanged += OnCoordinatorStateChanged;
        _mainWindow = new MainWindow(_coordinator);
        _window = _mainWindow;
        _mainWindow.Closed += OnWindowClosed;
        _mainWindow.Activate();
        _tray = TrayIconService.Start();
        _tray.CommandInvoked += OnTrayCommandInvoked;
        _tray.RoomSelected += OnTrayRoomSelected;
        try
        {
            await _coordinator.InitializeAsync();
        }
        catch (Exception exception)
        {
            _mainWindow.ShowFatalError(exception);
        }
    }

    private void RequestComposer()
    {
        _mainWindow?.DispatcherQueue.TryEnqueue(ShowComposer);
    }

    private void ShowComposer()
    {
        if (_coordinator is null)
        {
            return;
        }

        if (_composer is null)
        {
            _composer = new ComposerWindow();
            _composer.SendRequested += OnSendRequested;
            _composer.TypingChanged += OnTypingChanged;
        }

        _composer.ShowAndFocus(
            _coordinator.State.Preferences.OverlayRegion.MonitorIdentifier);
    }

    private void OnSendRequested(string body) => _ = SendAsync(body);

    private async Task SendAsync(string body)
    {
        if (_coordinator is null)
        {
            return;
        }

        try
        {
            await _coordinator.SendMessageAsync(body);
        }
        catch
        {
            // AppCoordinator restores the exact draft through SendFailed.
        }
    }

    private void OnTypingChanged(bool active)
    {
        if (_coordinator is not null)
        {
            _ = RunCoordinatorCommandAsync(() => _coordinator.SetTypingAsync(active));
        }
    }

    private void RequestPulse()
    {
        var mainWindow = _mainWindow;
        mainWindow?.DispatcherQueue.TryEnqueue(async () =>
        {
            if (_coordinator is null)
            {
                return;
            }

            try
            {
                await _coordinator.PulseCurrentCharacterAsync();
            }
            catch (Exception exception)
            {
                mainWindow.ShowFatalError(exception);
            }
        });
    }

    private void RestoreFailedDraft(string body) =>
        _mainWindow?.DispatcherQueue.TryEnqueue(() =>
        {
            ShowComposer();
            _composer?.RestoreDraftAndFocus(body);
        });

    private void OnRenderingFailed(Exception exception)
    {
        var mainWindow = _mainWindow;
        mainWindow?.DispatcherQueue.TryEnqueue(() => mainWindow.ShowFatalError(exception));
    }

    private void OnGroupSetupRequested()
    {
        var mainWindow = _mainWindow;
        mainWindow?.DispatcherQueue.TryEnqueue(() => mainWindow.ShowPage("groups"));
    }

    private void OnCoordinatorStateChanged(CoordinatorState state)
    {
        var mainWindow = _mainWindow;
        var coordinator = _coordinator;
        mainWindow?.DispatcherQueue.TryEnqueue(() =>
        {
            mainWindow.ApplyState(state);
            _tray?.SetState(new TrayMenuState(
                state.Preferences.OverlayVisible,
                state.Preferences.QuietMode,
                state.Preferences.StartAtLogin,
                coordinator?.TotalUnreadCount ?? 0,
                state.Rooms.Select(room => new TrayRoomMenuItem(
                    room.Id,
                    room.Name,
                    coordinator?.UnreadCount(room.Id) ?? 0)).ToArray(),
                state.ActiveRoomId));
        });
    }

    private void OnTrayCommandInvoked(TrayCommand command) =>
        _mainWindow?.DispatcherQueue.TryEnqueue(() => HandleTrayCommand(command));

    private void OnTrayRoomSelected(Guid roomId)
    {
        var mainWindow = _mainWindow;
        mainWindow?.DispatcherQueue.TryEnqueue(async () =>
        {
            if (_coordinator is null)
            {
                return;
            }

            try
            {
                await _coordinator.SwitchRoomAsync(roomId);
            }
            catch (Exception exception)
            {
                mainWindow.ShowFatalError(exception);
            }
        });
    }

    private void HandleTrayCommand(TrayCommand command)
    {
        if (_coordinator is null || _mainWindow is null)
        {
            return;
        }
        switch (command)
        {
            case TrayCommand.ToggleOverlay:
                _ = RunCoordinatorCommandAsync(
                    () => _coordinator.SetOverlayVisibleAsync(
                        !_coordinator.State.Preferences.OverlayVisible));
                break;
            case TrayCommand.Compose:
                _coordinator.RequestComposer();
                break;
            case TrayCommand.ToggleQuietMode:
                _ = RunCoordinatorCommandAsync(
                    () => _coordinator.SetQuietModeAsync(
                        !_coordinator.State.Preferences.QuietMode));
                break;
            case TrayCommand.History:
                _mainWindow.ShowPage("history");
                break;
            case TrayCommand.Groups:
                _mainWindow.ShowPage("groups");
                break;
            case TrayCommand.ToggleStartAtLogin:
                _ = RunCoordinatorCommandAsync(
                    () => _coordinator.SetStartAtLoginAsync(
                        !_coordinator.State.Preferences.StartAtLogin));
                break;
            case TrayCommand.CheckUpdates:
                _mainWindow.ShowPage("settings");
                _mainWindow.CheckForUpdates();
                break;
            case TrayCommand.Settings:
                _mainWindow.ShowPage("settings");
                break;
            case TrayCommand.Exit:
                _mainWindow.CloseForExit();
                break;
        }
    }

    private async Task RunCoordinatorCommandAsync(Func<Task> command)
    {
        try
        {
            await command();
        }
        catch (OperationCanceledException) when (_shuttingDown)
        {
        }
        catch (Exception exception)
        {
            var mainWindow = _mainWindow;
            mainWindow?.DispatcherQueue.TryEnqueue(
                () => mainWindow.ShowFatalError(exception));
        }
    }

    private async void OnWindowClosed(object sender, WindowEventArgs args)
    {
        _ = sender;
        _ = args;
        if (_shuttingDown)
        {
            return;
        }

        _shuttingDown = true;
        if (_tray is not null)
        {
            _tray.CommandInvoked -= OnTrayCommandInvoked;
            _tray.RoomSelected -= OnTrayRoomSelected;
            _tray.Dispose();
            _tray = null;
        }
        if (_composer is not null)
        {
            _composer.SendRequested -= OnSendRequested;
            _composer.TypingChanged -= OnTypingChanged;
            _composer.Close();
            _composer = null;
        }
        if (_coordinator is not null)
        {
            _coordinator.ComposerRequested -= RequestComposer;
            _coordinator.PulseRequested -= RequestPulse;
            _coordinator.SendFailed -= RestoreFailedDraft;
            _coordinator.RenderingFailed -= OnRenderingFailed;
            _coordinator.GroupSetupRequested -= OnGroupSetupRequested;
            _coordinator.StateChanged -= OnCoordinatorStateChanged;
            await _coordinator.DisposeAsync();
            _coordinator = null;
        }
        _singleInstance?.Dispose();
        _singleInstance = null;
        Exit();
    }
}
