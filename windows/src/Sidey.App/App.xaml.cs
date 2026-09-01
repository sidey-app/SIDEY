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
        StartupDiagnostics.BeginSession();
        AppDomain.CurrentDomain.UnhandledException += OnDomainUnhandledException;
        TaskScheduler.UnobservedTaskException += OnUnobservedTaskException;
        try
        {
            InitializeComponent();
            UnhandledException += OnXamlUnhandledException;
            StartupDiagnostics.Stage("xaml-initialized");
        }
        catch (Exception exception)
        {
            StartupDiagnostics.Fatal("app-xaml-initialization", exception, showDialog: true);
            throw;
        }
    }

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            await LaunchAsync(args);
        }
        catch (Exception exception)
        {
            StartupDiagnostics.Fatal("launch", exception, showDialog: _mainWindow is null);
            if (_mainWindow is not null)
            {
                _mainWindow.ShowFatalError(new InvalidOperationException(
                    "SIDEY 시작 중 오류가 발생했습니다. 앱을 종료한 뒤 다시 실행해 주세요.",
                    exception));
                return;
            }

            await DisposeAfterFailedLaunchAsync();
            Exit();
        }
    }

    private async Task LaunchAsync(LaunchActivatedEventArgs args)
    {
        _ = args;
        StartupDiagnostics.Stage("launch-entered");
        _singleInstance = SingleInstanceGuard.Acquire();
        if (!_singleInstance.IsPrimary)
        {
            StartupDiagnostics.Stage("secondary-instance-exit");
            Exit();
            return;
        }
        StartupDiagnostics.Stage("single-instance-acquired");

        if (!WindowsVersionGuard.IsSupported())
        {
            _window = new UnsupportedWindowsWindow();
            _window.Closed += OnWindowClosed;
            _window.Activate();
            StartupDiagnostics.Stage("unsupported-window-activated");
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
        StartupDiagnostics.Stage("main-window-activated");
        try
        {
            _tray = TrayIconService.Start();
            _tray.CommandInvoked += OnTrayCommandInvoked;
            _tray.RoomSelected += OnTrayRoomSelected;
            _mainWindow.SetTrayAvailable(true);
            StartupDiagnostics.Stage("tray-started");
        }
        catch (Exception exception)
        {
            StartupDiagnostics.NonFatal("tray-start", exception);
            _mainWindow.ShowFatalError(new InvalidOperationException(
                "트레이 아이콘을 시작하지 못했습니다. 창을 닫으면 SIDEY가 종료됩니다.",
                exception));
        }
        try
        {
            await _coordinator.InitializeAsync();
            StartupDiagnostics.Stage("coordinator-initialized");
        }
        catch (Exception exception)
        {
            StartupDiagnostics.NonFatal("coordinator-initialize", exception);
            _mainWindow.ShowFatalError(exception);
        }
    }

    private async Task DisposeAfterFailedLaunchAsync()
    {
        try
        {
            _tray?.Dispose();
        }
        catch (Exception exception)
        {
            StartupDiagnostics.NonFatal("failed-launch-tray-dispose", exception);
        }
        _tray = null;

        if (_coordinator is not null)
        {
            try
            {
                await _coordinator.DisposeAsync();
            }
            catch (Exception exception)
            {
                StartupDiagnostics.NonFatal("failed-launch-coordinator-dispose", exception);
            }
            _coordinator = null;
        }

        _singleInstance?.Dispose();
        _singleInstance = null;
    }

    private static void OnXamlUnhandledException(
        object sender,
        Microsoft.UI.Xaml.UnhandledExceptionEventArgs args)
    {
        _ = sender;
        StartupDiagnostics.Fatal("xaml-unhandled", args.Exception, showDialog: true);
    }

    private static void OnDomainUnhandledException(
        object sender,
        System.UnhandledExceptionEventArgs args)
    {
        _ = sender;
        var exception = args.ExceptionObject as Exception
            ?? new InvalidOperationException("A non-Exception object reached the unhandled exception boundary.");
        StartupDiagnostics.Fatal("app-domain-unhandled", exception, showDialog: true);
    }

    private static void OnUnobservedTaskException(object? sender, UnobservedTaskExceptionEventArgs args)
    {
        _ = sender;
        StartupDiagnostics.NonFatal("unobserved-task", args.Exception);
        args.SetObserved();
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
            try
            {
                _tray.Dispose();
            }
            catch (Exception exception)
            {
                StartupDiagnostics.NonFatal("shutdown-tray-dispose", exception);
            }
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
            try
            {
                await _coordinator.DisposeAsync();
            }
            catch (Exception exception)
            {
                StartupDiagnostics.NonFatal("shutdown-coordinator-dispose", exception);
            }
            _coordinator = null;
        }
        _singleInstance?.Dispose();
        _singleInstance = null;
        StartupDiagnostics.Stage("shutdown-complete");
        Exit();
    }
}
