using System.Diagnostics;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Sidey.Core.Localization;
using Sidey.Platform.Windows;
using Sidey.Presentation.Services;
using Sidey.Presentation.ViewModels;

namespace Sidey.App;

public partial class App : Application
{
    private static readonly TimeSpan ConnectionFailureNotificationDelay = TimeSpan.FromSeconds(15);
    private static readonly TimeSpan ConnectionFailureNotificationCooldown = TimeSpan.FromMinutes(15);

    private readonly DispatcherQueue _dispatcherQueue;
    private readonly IUpdateService _updateService;
    private Window? _window;
    private MainWindow? _mainWindow;
    private OnboardingWindow? _onboardingWindow;
    private HistoryWindow? _historyWindow;
    private ComposerWindow? _composer;
    private AppCoordinator? _coordinator;
    private SingleInstanceGuard? _singleInstance;
    private TrayIconService? _tray;
#if DEBUG
    private DevelopmentUpdateService? _developmentUpdate;
#endif
    private bool _startupUpdateCheckStarted;
    private bool _monitorConnectionFailures;
    private bool _connectionFailureNotificationArmed = true;
    private DateTimeOffset? _lastConnectionFailureNotificationAt;
    private DispatcherQueueTimer? _connectionFailureNotificationTimer;
    private string? _pendingUpdateNotificationVersion;
    private Timer? _uiResponsivenessTimer;
    private bool _shuttingDown;

    public App()
    {
        _dispatcherQueue = DispatcherQueue.GetForCurrentThread();
        _updateService = new WindowsUpdateServiceAdapter();
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
                    I18n.Get("error.launch"),
                    exception));
                return;
            }

            await DisposeAfterFailedLaunchAsync();
            Exit();
        }
    }

    private async Task LaunchAsync(LaunchActivatedEventArgs args)
    {
        string? processArguments = WindowsLaunchArguments.Resolve(
            activationArguments: null,
            Environment.GetCommandLineArgs());
        bool backgroundLaunch = WindowsStartupService.IsBackgroundLaunch(args.Arguments)
            || WindowsStartupService.IsBackgroundLaunch(processArguments);
        StartupDiagnostics.Stage("launch-entered");
        StartupDiagnostics.Stage($"launch-mode background={backgroundLaunch}");
        _singleInstance = SingleInstanceGuard.Acquire();
        if (!_singleInstance.IsPrimary)
        {
            _singleInstance.Signal();
            StartupDiagnostics.Stage("secondary-instance-request request=activate");
            _singleInstance.Dispose();
            _singleInstance = null;
            StartupDiagnostics.CompleteSession();
            Exit();
            return;
        }
        StartupDiagnostics.Stage("single-instance-acquired");

        if (!WindowsVersionGuard.CanLaunchMainWindow())
        {
            _window = new UnsupportedWindowsWindow();
            _window.Closed += OnWindowClosed;
            _window.Activate();
            StartupDiagnostics.Stage("unsupported-window-activated");
            StartupDiagnostics.MarkRunning();
            StartUiResponsivenessMonitor();
            return;
        }

        _coordinator = new AppCoordinator();
        await _coordinator.LoadCachedStateAsync();
        StartupDiagnostics.Stage("cached-settings-loaded");
        _coordinator.ComposerRequested += RequestComposer;
        _coordinator.PulseRequested += RequestPulse;
        _coordinator.CharacterThrowRequested += RequestCharacterThrow;
        _coordinator.SendFailed += RestoreFailedDraft;
        _coordinator.RenderingFailed += OnRenderingFailed;
        _coordinator.GroupSetupRequested += OnGroupSetupRequested;
        _coordinator.StateChanged += OnCoordinatorStateChanged;
        if (!_coordinator.State.Preferences.OnboardingCompleted)
        {
            CreateOnboardingWindow(_coordinator);
            _window = _onboardingWindow;
            _onboardingWindow!.Activate();
            StartupDiagnostics.Stage("onboarding-window-activated");
        }
        else
        {
            EnsureMainWindow();
            _window = _mainWindow;
            StartupDiagnostics.Stage("completed-launch-window-hidden");
        }
        _singleInstance!.StartListening(RequestPrimaryActivation);
        try
        {
            _tray = TrayIconService.Start();
            _tray.CommandInvoked += OnTrayCommandInvoked;
            _tray.RoomSelected += OnTrayRoomSelected;
            _mainWindow?.SetTrayAvailable(true);
            StartupDiagnostics.Stage("tray-started");
            if (_pendingUpdateNotificationVersion is { } pendingVersion)
            {
                PostUpdateNotification(pendingVersion);
            }
        }
        catch (Exception exception)
        {
            StartupDiagnostics.NonFatal("tray-start", exception);
            EnsureMainWindow().ShowFatalError(new InvalidOperationException(
                I18n.Get("error.trayStart"),
                exception));
        }
#if DEBUG
        _developmentUpdate = DevelopmentUpdateService.Start(OnDevelopmentUpdateAccepted);
#endif
        try
        {
            await _coordinator.InitializeAsync();
            StartupDiagnostics.Stage("coordinator-initialized");
        }
        catch (Exception exception)
        {
            StartupDiagnostics.NonFatal("coordinator-initialize", exception);
            EnsureMainWindow().ShowFatalError(exception);
            _onboardingWindow?.ShowError(exception);
        }

        _monitorConnectionFailures = true;
        UpdateConnectionFailureNotification(_coordinator.State.Connected);

        StartupDiagnostics.MarkRunning();
        StartUiResponsivenessMonitor();
    }

    private void StartUiResponsivenessMonitor()
    {
        _uiResponsivenessTimer ??= new Timer(
            static state => ((App)state!).ProbeUiResponsiveness(),
            this,
            TimeSpan.FromMinutes(1),
            TimeSpan.FromMinutes(1));
    }

    private void ProbeUiResponsiveness()
    {
        if (_shuttingDown)
        {
            return;
        }

        long started = Stopwatch.GetTimestamp();
        if (!_dispatcherQueue.TryEnqueue(() =>
            StartupDiagnostics.Stage(
                $"ui-heartbeat delay-ms={(long)Stopwatch.GetElapsedTime(started).TotalMilliseconds}")))
        {
            StartupDiagnostics.Stage("ui-heartbeat dispatch=failed");
        }
    }

    private void StartStartupUpdateCheck()
    {
        if (_startupUpdateCheckStarted || _mainWindow is null)
        {
            return;
        }

        _startupUpdateCheckStarted = true;
        _ = CheckForUpdatesOnStartupAsync(_mainWindow);
    }

    private MainWindow EnsureMainWindow()
    {
        if (_mainWindow is not null)
        {
            return _mainWindow;
        }

        if (_coordinator is null)
        {
            throw new InvalidOperationException("The settings window requires an initialized coordinator.");
        }

        _mainWindow = new MainWindow(_coordinator, _updateService);
        StartupDiagnostics.Stage("settings-window-created result=success");
        _mainWindow.Closed += OnMainWindowClosed;
        _mainWindow.SetTrayAvailable(_tray is not null);
        StartStartupUpdateCheck();
        return _mainWindow;
    }

    private async Task CheckForUpdatesOnStartupAsync(MainWindow mainWindow)
    {
        try
        {
            StartupDiagnostics.Stage("startup-update-check-started");
            AvailableUpdate? update = await mainWindow.ViewModel.CheckForUpdatesOnStartupAsync();
            StartupDiagnostics.Stage("startup-update-checked");
            if (update is not null)
            {
                PostUpdateNotification(update.Version);
            }
        }
        catch (Exception exception)
        {
            StartupDiagnostics.NonFatal("startup-update-check", exception);
        }
    }

    private void PostUpdateNotification(string version)
    {
        if (_tray is null)
        {
            _pendingUpdateNotificationVersion = version;
            return;
        }

        _pendingUpdateNotificationVersion = null;
        _tray.NotifyUpdateAvailable(version);
        StartupDiagnostics.Stage("update-available-notification-posted");
    }

    private async Task DisposeAfterFailedLaunchAsync()
    {
#if DEBUG
        _developmentUpdate?.Dispose();
        _developmentUpdate = null;
#endif
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
        _dispatcherQueue.TryEnqueue(ShowComposer);
    }

    private void ShowComposer()
    {
        if (_coordinator is null)
        {
            return;
        }

        if (_composer is null)
        {
            var viewModel = new ComposerViewModel();
            viewModel.SendRequested += OnSendRequested;
            viewModel.TypingChanged += OnTypingChanged;
            _composer = new ComposerWindow(viewModel);
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
        _dispatcherQueue.TryEnqueue(async () =>
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
                EnsureMainWindow().ShowFatalError(exception);
            }
        });
    }

    private void RequestCharacterThrow(Guid targetUserId)
    {
        _dispatcherQueue.TryEnqueue(async () =>
        {
            if (_coordinator is null)
            {
                return;
            }

            try
            {
                await _coordinator.ThrowAtCharacterAsync(targetUserId);
            }
            catch (Exception exception)
            {
                StartupDiagnostics.NonFatal("character-throw", exception);
            }
        });
    }

    private void RestoreFailedDraft(string body, Exception exception) =>
        _dispatcherQueue.TryEnqueue(() =>
        {
            ShowComposer();
            _composer?.RestoreDraftAndFocus(body);
            MainWindow mainWindow = EnsureMainWindow();
            mainWindow.ShowFatalError(new InvalidOperationException(
                I18n.Format("error.messageSendFailed", exception.Message),
                exception));
            ShowPrimaryWindow();
        });

    private void OnRenderingFailed(Exception exception)
    {
        StartupDiagnostics.NonFatal("overlay-render", exception);
        _dispatcherQueue.TryEnqueue(() => EnsureMainWindow().ShowFatalError(exception));
    }

    private void OnGroupSetupRequested()
    {
        _dispatcherQueue.TryEnqueue(() => EnsureMainWindow().ShowPage("groups"));
    }

    private void OnOnboardingCompleted()
    {
        if (_onboardingWindow is null)
        {
            return;
        }

        MainWindow mainWindow = EnsureMainWindow();
        OnboardingWindow onboarding = _onboardingWindow;
        _onboardingWindow = null;
        onboarding.Completed -= OnOnboardingCompleted;
        onboarding.Closed -= OnOnboardingClosed;
        _window = mainWindow;
        mainWindow.Activate();
        SideyWindowActivation.BringToForeground(mainWindow);
        onboarding.Close();
        StartupDiagnostics.Stage("onboarding-completed");
    }

    private void CreateOnboardingWindow(AppCoordinator coordinator)
    {
        _onboardingWindow = new OnboardingWindow(coordinator);
        _onboardingWindow.Completed += OnOnboardingCompleted;
        _onboardingWindow.Closed += OnOnboardingClosed;
    }

    private void OnOnboardingClosed(object sender, WindowEventArgs args)
    {
        _ = args;
        if (!ReferenceEquals(sender, _onboardingWindow))
        {
            return;
        }

        _onboardingWindow!.Completed -= OnOnboardingCompleted;
        _onboardingWindow.Closed -= OnOnboardingClosed;
        _onboardingWindow = null;
        BeginShutdown();
    }

    private void RequestPrimaryActivation()
    {
        _dispatcherQueue.TryEnqueue(() =>
        {
            if (_onboardingWindow is null
                && _coordinator is not null
                && !_coordinator.State.Preferences.OnboardingCompleted)
            {
                CreateOnboardingWindow(_coordinator);
                _window = _onboardingWindow;
            }

            if (_onboardingWindow is not null)
            {
                _onboardingWindow.ShowAndActivate();
            }
        });
    }

    private void ShowPrimaryWindow()
    {
        MainWindow mainWindow = EnsureMainWindow();
        _window = mainWindow;
        mainWindow.AppWindow.Show();
        mainWindow.Activate();
        SideyWindowActivation.BringToForeground(mainWindow);
    }

    private void OnCoordinatorStateChanged(CoordinatorState state)
    {
        var coordinator = _coordinator;
        _dispatcherQueue.TryEnqueue(() =>
        {
            UpdateConnectionFailureNotification(state.Connected);
            _mainWindow?.ApplyState(state);
            _onboardingWindow?.ApplyState(state);
            _historyWindow?.ApplyState(state);
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
        _dispatcherQueue.TryEnqueue(() => HandleTrayCommand(command));

    private void OnTrayRoomSelected(Guid roomId)
    {
        _dispatcherQueue.TryEnqueue(async () =>
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
                EnsureMainWindow().ShowFatalError(exception);
            }
        });
    }

    private void HandleTrayCommand(TrayCommand command)
    {
        if (_coordinator is null)
        {
            return;
        }
        if (_onboardingWindow is null
            && !_coordinator.State.Preferences.OnboardingCompleted
            && command != TrayCommand.Exit)
        {
            CreateOnboardingWindow(_coordinator);
            _window = _onboardingWindow;
        }
        if (_onboardingWindow is not null && command != TrayCommand.Exit)
        {
            _onboardingWindow.ShowAndActivate();
            return;
        }
        switch (command)
        {
            case TrayCommand.Open:
                ShowPrimaryWindow();
                break;
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
                ShowHistory();
                break;
            case TrayCommand.Groups:
                EnsureMainWindow().ShowPage("groups");
                break;
            case TrayCommand.ToggleStartAtLogin:
                _ = RunCoordinatorCommandAsync(
                    () => _coordinator.SetStartAtLoginAsync(
                        !_coordinator.State.Preferences.StartAtLogin));
                break;
            case TrayCommand.CheckUpdates:
                EnsureMainWindow().ShowPage("settings");
                _mainWindow!.CheckForUpdates();
                break;
            case TrayCommand.Settings:
                EnsureMainWindow().ShowPage("settings");
                break;
            case TrayCommand.Store:
                EnsureMainWindow().ShowPage("store");
                break;
            case TrayCommand.Exit:
                BeginShutdown();
                break;
        }
    }

    private void UpdateConnectionFailureNotification(bool connected)
    {
        if (connected)
        {
            _connectionFailureNotificationArmed = true;
            CancelConnectionFailureNotification();
            return;
        }

        if (_shuttingDown
            || !_monitorConnectionFailures
            || !_connectionFailureNotificationArmed)
        {
            return;
        }

        ScheduleConnectionFailureNotification();
    }

    private void ScheduleConnectionFailureNotification()
    {
        if (_connectionFailureNotificationTimer is not null)
        {
            return;
        }

        var timer = _dispatcherQueue.CreateTimer();
        timer.Interval = ConnectionFailureNotificationDelay;
        timer.IsRepeating = false;
        timer.Tick += OnConnectionFailureNotificationElapsed;
        _connectionFailureNotificationTimer = timer;
        timer.Start();
        StartupDiagnostics.Stage(
            $"connection-failure-notification-deferred delay-ms={(long)ConnectionFailureNotificationDelay.TotalMilliseconds}");
    }

    private void OnConnectionFailureNotificationElapsed(
        DispatcherQueueTimer sender,
        object args)
    {
        _ = args;
        sender.Tick -= OnConnectionFailureNotificationElapsed;
        sender.Stop();
        if (ReferenceEquals(_connectionFailureNotificationTimer, sender))
        {
            _connectionFailureNotificationTimer = null;
        }

        if (!_shuttingDown && _coordinator?.State.Connected == false)
        {
            PostConnectionFailureNotification();
        }
    }

    private void CancelConnectionFailureNotification()
    {
        if (_connectionFailureNotificationTimer is not { } timer)
        {
            return;
        }

        timer.Tick -= OnConnectionFailureNotificationElapsed;
        timer.Stop();
        _connectionFailureNotificationTimer = null;
        StartupDiagnostics.Stage("connection-failure-notification-deferred result=cancelled");
    }

    private void PostConnectionFailureNotification()
    {
        if (_tray is null)
        {
            return;
        }

        _connectionFailureNotificationArmed = false;
        DateTimeOffset now = DateTimeOffset.UtcNow;
        if (_lastConnectionFailureNotificationAt is { } previous
            && now - previous < ConnectionFailureNotificationCooldown)
        {
            return;
        }

        _lastConnectionFailureNotificationAt = now;
        _tray.NotifyConnectionFailure();
        StartupDiagnostics.Stage("connection-failure-notification-posted");
    }

    private void ShowHistory()
    {
        if (_coordinator is null)
        {
            return;
        }
        if (_historyWindow is null)
        {
            _historyWindow = new HistoryWindow(new HistoryWindowViewModel(_coordinator));
            _historyWindow.Closed += (_, _) => _historyWindow = null;
        }
        _historyWindow.ShowAndActivate();
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
            _dispatcherQueue.TryEnqueue(
                () => EnsureMainWindow().ShowFatalError(exception));
        }
    }

    private void OnWindowClosed(object sender, WindowEventArgs args)
    {
        _ = sender;
        _ = args;
        BeginShutdown();
    }

    private void OnMainWindowClosed(object sender, WindowEventArgs args)
    {
        _ = args;
        if (sender is not MainWindow mainWindow || !ReferenceEquals(mainWindow, _mainWindow))
        {
            return;
        }

        bool shouldExit = mainWindow.ShouldExitOnClose;
        mainWindow.Closed -= OnMainWindowClosed;
        _mainWindow = null;
        if (ReferenceEquals(_window, mainWindow))
        {
            _window = null;
        }

        if (shouldExit)
        {
            BeginShutdown();
        }
    }

    private async void BeginShutdown()
    {
        if (_shuttingDown)
        {
            return;
        }

        _shuttingDown = true;
        CancelConnectionFailureNotification();
        _uiResponsivenessTimer?.Dispose();
        _uiResponsivenessTimer = null;
        if (_mainWindow is not null)
        {
            MainWindow mainWindow = _mainWindow;
            _mainWindow = null;
            mainWindow.Closed -= OnMainWindowClosed;
            mainWindow.CloseForExit();
        }
#if DEBUG
        _developmentUpdate?.Dispose();
        _developmentUpdate = null;
#endif
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
            _composer.ViewModel.SendRequested -= OnSendRequested;
            _composer.ViewModel.TypingChanged -= OnTypingChanged;
            _composer.Close();
            _composer = null;
        }
        if (_historyWindow is not null)
        {
            _historyWindow.Close();
            _historyWindow = null;
        }
        if (_onboardingWindow is not null)
        {
            _onboardingWindow.Completed -= OnOnboardingCompleted;
            _onboardingWindow.Closed -= OnOnboardingClosed;
            _onboardingWindow.Close();
            _onboardingWindow = null;
        }
        if (_coordinator is not null)
        {
            _coordinator.ComposerRequested -= RequestComposer;
            _coordinator.PulseRequested -= RequestPulse;
            _coordinator.CharacterThrowRequested -= RequestCharacterThrow;
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
        StartupDiagnostics.CompleteSession();
        Exit();
    }

#if DEBUG
    private void OnDevelopmentUpdateAccepted(DevelopmentUpdateRequest request)
    {
        if (_shuttingDown || _developmentUpdate is null)
        {
            return;
        }
        try
        {
            if (_developmentUpdate.LaunchUpdater(request))
            {
                // This callback runs on the watcher thread so it remains
                // independent from UI and network initialization stalls.
                StartupDiagnostics.Stage("update-handoff-complete");
                StartupDiagnostics.CompleteSession();
                Environment.Exit(0);
            }
        }
        catch (Exception exception)
        {
            StartupDiagnostics.NonFatal("development-update-start", exception);
        }
    }
#endif
}
