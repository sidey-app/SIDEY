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
    private static readonly TimeSpan DisplayTopologyRefreshDelay = TimeSpan.FromMilliseconds(500);

    private readonly DispatcherQueue _dispatcherQueue;
    private readonly WindowsUpdateServiceAdapter _updateService;
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
    private DispatcherQueueTimer? _displayTopologyRefreshTimer;
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
        catch (Exception) when (_shuttingDown)
        {
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
            _singleInstance.Signal(processArguments);
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

        var coordinator = new AppCoordinator();
        _coordinator = coordinator;
        await coordinator.LoadCachedStateAsync();
        if (_shuttingDown || !ReferenceEquals(_coordinator, coordinator))
        {
            return;
        }

        StartupDiagnostics.Stage("cached-settings-loaded");
        coordinator.ComposerRequested += RequestComposer;
        coordinator.PulseRequested += RequestPulse;
        coordinator.CharacterThrowRequested += RequestCharacterThrow;
        coordinator.SendFailed += RestoreFailedDraft;
        coordinator.RenderingFailed += OnRenderingFailed;
        coordinator.GroupSetupRequested += OnGroupSetupRequested;
        coordinator.StateChanged += OnCoordinatorStateChanged;
        if (!coordinator.State.Preferences.OnboardingCompleted)
        {
            CreateOnboardingWindow(coordinator);
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
        await RunComposerStartupSmokeIfRequestedAsync();
        _singleInstance!.StartListening(RequestPrimaryActivation);
        try
        {
            _tray = TrayIconService.Start();
            _tray.CommandInvoked += OnTrayCommandInvoked;
            _tray.RoomSelected += OnTrayRoomSelected;
            _tray.DisplayTopologyChanged += OnDisplayTopologyChanged;
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
            await coordinator.InitializeAsync();
            if (_shuttingDown || !ReferenceEquals(_coordinator, coordinator))
            {
                return;
            }

            StartupDiagnostics.Stage("coordinator-initialized");
#if SIDEY_DEVELOPMENT_COMMERCE
            if (coordinator.State.DevelopmentCommerceEnabled
                && Environment.ProcessPath is { } executablePath)
            {
                WindowsProtocolRegistration.EnsureCurrentUserDevelopmentCallback(executablePath);
            }
#endif
            await TryHandleActivationRequestAsync(processArguments);
        }
        catch (Exception exception)
        {
            StartupDiagnostics.NonFatal("coordinator-initialize", exception);
            if (_shuttingDown || !ReferenceEquals(_coordinator, coordinator))
            {
                return;
            }

            EnsureMainWindow().ShowFatalError(exception);
            _onboardingWindow?.ShowError(exception);
        }

        if (_shuttingDown || !ReferenceEquals(_coordinator, coordinator))
        {
            return;
        }

        _monitorConnectionFailures = true;
        UpdateConnectionFailureNotification(coordinator.State.Connected);

        StartupDiagnostics.MarkRunning();
        StartUiResponsivenessMonitor();
        _ = _updateService.CleanupInstalledUpdatesAsync();
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
        if (_shuttingDown || _startupUpdateCheckStarted || _mainWindow is null)
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
            if (!_shuttingDown
                && ReferenceEquals(_mainWindow, mainWindow)
                && update is not null)
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
        if (_shuttingDown)
        {
            return;
        }

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
        if (_shuttingDown)
        {
            return;
        }

        _dispatcherQueue.TryEnqueue(() =>
        {
            if (!_shuttingDown)
            {
                ShowComposer();
            }
        });
    }

    private void ShowComposer()
    {
        if (_shuttingDown || _coordinator is null)
        {
            return;
        }

        if (_composer is null)
        {
            var viewModel = new ComposerViewModel();
            viewModel.SendRequested += OnSendRequested;
            viewModel.TypingChanged += OnTypingChanged;
            try
            {
                StartupDiagnostics.Stage("composer-window-create-started");
                _composer = new ComposerWindow(viewModel);
                StartupDiagnostics.Stage("composer-window-created");
            }
            catch (Exception exception)
            {
                viewModel.SendRequested -= OnSendRequested;
                viewModel.TypingChanged -= OnTypingChanged;
                viewModel.Dispose();
                StartupDiagnostics.NonFatal("composer-window-create", exception);
                return;
            }
        }

        _composer.ShowAndFocus(
            _coordinator.State.Preferences.OverlayRegion.MonitorIdentifier);
    }

    private static async Task RunComposerStartupSmokeIfRequestedAsync()
    {
        if (!string.Equals(
                Environment.GetEnvironmentVariable(
                    WindowsVersionGuard.StartupSmokeEnvironmentVariable),
                "1",
                StringComparison.Ordinal))
        {
            return;
        }

        for (var windowIndex = 0; windowIndex < 5; windowIndex++)
        {
            var viewModel = new ComposerViewModel();
            var composer = new ComposerWindow(viewModel);
            var input = (Microsoft.UI.Xaml.Controls.TextBox)
                ((FrameworkElement)composer.Content).FindName("MessageInput");
            viewModel.Draft = "한글 입력 테스트 ABC";
            for (var cycle = 0; cycle < 10; cycle++)
            {
                composer.ShowAndFocus(monitorIdentifier: null);
                await Task.Delay(150);
                if (composer.AppWindow.ClientSize.Width != composer.AppWindow.Size.Width
                    || composer.AppWindow.ClientSize.Height != composer.AppWindow.Size.Height
                    || input.FocusState == FocusState.Unfocused
                    || input.Text != viewModel.Draft)
                {
                    StartupDiagnostics.Stage(
                        $"composer-smoke-check window={composer.AppWindow.Size.Width}x{composer.AppWindow.Size.Height} " +
                        $"client={composer.AppWindow.ClientSize.Width}x{composer.AppWindow.ClientSize.Height} " +
                        $"focus={input.FocusState} draft-match={input.Text == viewModel.Draft}");
                    throw new InvalidOperationException(
                        "The startup composer probe lost its borderless layout, focus, or draft.");
                }

                // Exercise explicit hiding and the same command used by X/Escape.
                if (cycle % 2 == 0)
                {
                    composer.HideComposer();
                }
                else
                {
                    viewModel.CloseCommand.Execute(null);
                }
                await Task.Delay(70);
                if (composer.AppWindow.IsVisible)
                {
                    throw new InvalidOperationException("The startup composer probe did not hide.");
                }
            }

            composer.CloseForExit();
            await Task.Delay(70);
        }

        StartupDiagnostics.Stage("composer-smoke-complete");
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
        if (_shuttingDown)
        {
            return;
        }

        _dispatcherQueue.TryEnqueue(async () =>
        {
            if (_shuttingDown || _coordinator is null)
            {
                return;
            }

            try
            {
                await _coordinator.PulseCurrentCharacterAsync();
            }
            catch (Exception exception)
            {
                if (!_shuttingDown)
                {
                    EnsureMainWindow().ShowFatalError(exception);
                }
            }
        });
    }

    private void RequestCharacterThrow(Guid targetUserId)
    {
        if (_shuttingDown)
        {
            return;
        }

        _dispatcherQueue.TryEnqueue(async () =>
        {
            if (_shuttingDown || _coordinator is null)
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

    private void RestoreFailedDraft(string body, Exception exception)
    {
        if (_shuttingDown)
        {
            return;
        }

        _dispatcherQueue.TryEnqueue(() =>
        {
            if (_shuttingDown)
            {
                return;
            }

            ShowComposer();
            _composer?.RestoreDraftAndFocus(body);
            MainWindow mainWindow = EnsureMainWindow();
            mainWindow.ShowFatalError(new InvalidOperationException(
                I18n.Format("error.messageSendFailed", exception.Message),
                exception));
            ShowPrimaryWindow();
        });
    }

    private void OnRenderingFailed(Exception exception)
    {
        StartupDiagnostics.NonFatal("overlay-render", exception);
        if (!_shuttingDown)
        {
            _dispatcherQueue.TryEnqueue(() =>
            {
                if (!_shuttingDown)
                {
                    EnsureMainWindow().ShowFatalError(exception);
                }
            });
        }
    }

    private void OnGroupSetupRequested()
    {
        if (!_shuttingDown)
        {
            _dispatcherQueue.TryEnqueue(() =>
            {
                if (!_shuttingDown)
                {
                    EnsureMainWindow().ShowPage("groups");
                }
            });
        }
    }

    private void OnOnboardingCompleted()
    {
        if (_shuttingDown || _onboardingWindow is null)
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

    private void RequestPrimaryActivation(string? activationArgument)
    {
        if (_shuttingDown)
        {
            return;
        }

        _dispatcherQueue.TryEnqueue(async () =>
        {
            if (_shuttingDown)
            {
                return;
            }

            if (await TryHandleActivationRequestAsync(activationArgument))
            {
                return;
            }
            if (_shuttingDown)
            {
                return;
            }

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
                return;
            }

            ShowPrimaryWindow();
        });
    }

    private async Task<bool> TryHandleActivationRequestAsync(string? activationArgument)
    {
        if (_shuttingDown || _coordinator is null)
        {
            return false;
        }
        string expectedScheme = _coordinator.State.DevelopmentCommerceEnabled
            ? WindowsAuthCallback.DevelopmentScheme
            : WindowsAuthCallback.ProductionScheme;
        if (!WindowsAuthCallback.TryGetCode(
            activationArgument,
            expectedScheme,
            out Uri? callbackUri,
            out _))
        {
            return false;
        }

        MainWindow mainWindow = EnsureMainWindow();
        mainWindow.ShowPage("store");
        try
        {
            await _coordinator.CompleteGoogleIdentityLinkAsync(callbackUri!);
            if (!_shuttingDown && ReferenceEquals(_mainWindow, mainWindow))
            {
                mainWindow.ViewModel.ReportSuccess(I18n.Get("store.googleConnected"));
            }
        }
        catch (Exception exception)
        {
            if (!_shuttingDown && ReferenceEquals(_mainWindow, mainWindow))
            {
                mainWindow.ViewModel.ReportError(exception);
            }
        }
        return true;
    }

    private void ShowPrimaryWindow()
    {
        if (_shuttingDown)
        {
            return;
        }

        MainWindow mainWindow = EnsureMainWindow();
        _window = mainWindow;
        mainWindow.AppWindow.Show();
        mainWindow.Activate();
        SideyWindowActivation.BringToForeground(mainWindow);
    }

    private void OnCoordinatorStateChanged(CoordinatorState state)
    {
        if (_shuttingDown)
        {
            return;
        }

        var coordinator = _coordinator;
        _dispatcherQueue.TryEnqueue(() =>
        {
            if (_shuttingDown)
            {
                return;
            }

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

    private void OnTrayCommandInvoked(TrayCommand command)
    {
        if (!_shuttingDown)
        {
            _dispatcherQueue.TryEnqueue(() =>
            {
                if (!_shuttingDown)
                {
                    HandleTrayCommand(command);
                }
            });
        }
    }

    private void OnTrayRoomSelected(Guid roomId)
    {
        if (_shuttingDown)
        {
            return;
        }

        _dispatcherQueue.TryEnqueue(async () =>
        {
            if (_shuttingDown || _coordinator is null)
            {
                return;
            }

            try
            {
                await _coordinator.SwitchRoomAsync(roomId);
            }
            catch (Exception exception)
            {
                if (!_shuttingDown)
                {
                    EnsureMainWindow().ShowFatalError(exception);
                }
            }
        });
    }

    private void OnDisplayTopologyChanged()
    {
        if (_shuttingDown)
        {
            return;
        }

        _dispatcherQueue.TryEnqueue(ScheduleDisplayTopologyRefresh);
    }

    private void ScheduleDisplayTopologyRefresh()
    {
        if (_shuttingDown)
        {
            return;
        }

        if (_displayTopologyRefreshTimer is { } pending)
        {
            pending.Stop();
            pending.Start();
            return;
        }

        var timer = _dispatcherQueue.CreateTimer();
        timer.Interval = DisplayTopologyRefreshDelay;
        timer.IsRepeating = false;
        timer.Tick += OnDisplayTopologyRefreshElapsed;
        _displayTopologyRefreshTimer = timer;
        timer.Start();
    }

    private void OnDisplayTopologyRefreshElapsed(DispatcherQueueTimer sender, object args)
    {
        _ = args;
        sender.Tick -= OnDisplayTopologyRefreshElapsed;
        sender.Stop();
        if (ReferenceEquals(_displayTopologyRefreshTimer, sender))
        {
            _displayTopologyRefreshTimer = null;
        }

        if (_shuttingDown || _coordinator is null)
        {
            return;
        }

        try
        {
            _coordinator.RefreshDisplayTopology();
            _mainWindow?.RefreshMonitors();
        }
        catch (Exception exception)
        {
            StartupDiagnostics.NonFatal("display-topology-refresh", exception);
            _mainWindow?.ShowFatalError(exception);
        }
    }

    private void CancelDisplayTopologyRefresh()
    {
        if (_displayTopologyRefreshTimer is not { } timer)
        {
            return;
        }

        timer.Tick -= OnDisplayTopologyRefreshElapsed;
        timer.Stop();
        _displayTopologyRefreshTimer = null;
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
        if (_shuttingDown || _coordinator is null)
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
            if (!_shuttingDown)
            {
                _dispatcherQueue.TryEnqueue(() =>
                {
                    if (!_shuttingDown)
                    {
                        EnsureMainWindow().ShowFatalError(exception);
                    }
                });
            }
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
        _monitorConnectionFailures = false;
        CancelConnectionFailureNotification();
        CancelDisplayTopologyRefresh();
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
            _tray.DisplayTopologyChanged -= OnDisplayTopologyChanged;
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
            _composer.CloseForExit();
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
