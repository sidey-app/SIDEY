using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Sidey.Core.Localization;
using Sidey.Platform.Windows;
using Sidey.Presentation.Services;
using Sidey.Presentation.ViewModels;

namespace Sidey.App;

public sealed partial class MainWindow : Window, IMainWindowDialogService
{
    private readonly DispatcherTimer _statusDismissTimer = new()
    {
        Interval = TimeSpan.FromSeconds(4),
    };

#if DEBUG
    private readonly DispatcherTimer _validationMetricsTimer = new()
    {
        Interval = TimeSpan.FromSeconds(1),
    };
#endif

    private bool _allowClose;
    private bool _trayAvailable;
    private bool _navigatingBack;
    private string _currentNavigationTag = "profile";
    private readonly Stack<string> _navigationHistory = new();
    private readonly WindowsMinimumSizeController _minimumSizeController;

    public MainWindow(AppCoordinator coordinator)
    {
        InitializeComponent();
        ViewModel = new MainWindowViewModel(coordinator, this, new WindowsUpdateServiceAdapter());
        MainRoot.DataContext = ViewModel;
        ViewModel.PrepareGroupsForPresentation();
        Title = "SIDEY";
        SideyWindowIcon.Apply(AppWindow);
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        RootNavigation.SelectedItem = RootNavigation.MenuItems[0];
        ResponsiveWindowSize minimumWindowSize = ApplyResponsiveSize();
        _minimumSizeController = new WindowsMinimumSizeController(
            WinRT.Interop.WindowNative.GetWindowHandle(this),
            minimumWindowSize);
        ApplyBackdrop();
        AppWindow.Closing += OnAppWindowClosing;
        Closed += OnWindowClosed;
        ViewModel.NoticeRaised += OnNoticeRaised;
        _statusDismissTimer.Tick += OnStatusDismissTimerTick;
#if DEBUG
        _validationMetricsTimer.Tick += OnValidationMetricsTimerTick;
        _validationMetricsTimer.Start();
#endif
    }

    public MainWindowViewModel ViewModel { get; }

    public bool ShouldExitOnClose => _allowClose || !_trayAvailable;

    public void ApplyState(CoordinatorState state) => ViewModel.ApplyState(state);

    public void ShowFatalError(Exception exception) => ViewModel.ReportError(exception);

    public void ShowPage(string tag)
    {
        ViewModel.PrepareGroupsForPresentation();
        NavigationViewItem? item = RootNavigation.MenuItems
            .OfType<NavigationViewItem>()
            .FirstOrDefault(candidate =>
                StringComparer.Ordinal.Equals(candidate.Tag as string, tag));
        if (item is not null)
        {
            RootNavigation.SelectedItem = item;
        }

        AppWindow.Show();
        Activate();
        SideyWindowActivation.BringToForeground(this);
    }

    public void CloseForExit()
    {
        _allowClose = true;
        Close();
    }

    public void SetTrayAvailable(bool available) => _trayAvailable = available;

    public void CheckForUpdates()
    {
        if (ViewModel.CheckForUpdatesCommand.CanExecute(null))
        {
            ViewModel.CheckForUpdatesCommand.Execute(null);
        }
    }

    public async Task<bool> ConfirmInviteCodeRotationAsync()
    {
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = I18n.Get("dialogs.rotateInviteTitle"),
            Content = I18n.Get("dialogs.rotateInviteBody"),
            PrimaryButtonText = I18n.Get("dialogs.rotateInvitePrimary"),
            CloseButtonText = I18n.Get("common.cancel"),
            DefaultButton = ContentDialogButton.Close,
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    public async Task<string?> PromptForRoomNameAsync(string currentName)
    {
        var input = new TextBox
        {
            Text = currentName,
            MaxLength = 20,
            PlaceholderText = I18n.Get("dialogs.roomNamePlaceholder"),
        };
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = I18n.Get("groups.renameDialogTitle"),
            Content = input,
            PrimaryButtonText = I18n.Get("common.save"),
            CloseButtonText = I18n.Get("common.cancel"),
            DefaultButton = ContentDialogButton.Primary,
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary
            ? input.Text
            : null;
    }

    public async Task<bool> ConfirmMemberRemovalAsync(string nickname)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = I18n.Format("dialogs.removeMemberTitle", nickname),
            Content = I18n.Format("dialogs.removeMemberBody", nickname),
            PrimaryButtonText = I18n.Get("dialogs.removeMemberPrimary"),
            CloseButtonText = I18n.Get("common.cancel"),
            DefaultButton = ContentDialogButton.Close,
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    public async Task<bool> ConfirmRoomLeaveAsync(string roomName, bool isOwner)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = I18n.Format("dialogs.leaveRoomTitle", roomName),
            Content = I18n.Get(isOwner
                ? "dialogs.leaveOwnedRoomBody"
                : "dialogs.leaveRoomBody"),
            PrimaryButtonText = I18n.Get("dialogs.leaveRoomPrimary"),
            CloseButtonText = I18n.Get("common.cancel"),
            DefaultButton = ContentDialogButton.Close,
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    public async Task<bool> ConfirmRoomDeletionAsync(string roomName)
    {
        var impactDialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = I18n.Format("dialogs.deleteRoomTitle", roomName),
            Content = I18n.Get("dialogs.deleteRoomBody"),
            PrimaryButtonText = I18n.Get("dialogs.deleteRoomContinue"),
            CloseButtonText = I18n.Get("common.cancel"),
            DefaultButton = ContentDialogButton.Close,
        };
        if (await impactDialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return false;
        }

        var finalDialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = I18n.Get("dialogs.deleteRoomFinalTitle"),
            Content = I18n.Format("dialogs.deleteRoomFinalBody", roomName),
            PrimaryButtonText = I18n.Get("common.delete"),
            CloseButtonText = I18n.Get("common.cancel"),
            DefaultButton = ContentDialogButton.Close,
        };
        return await finalDialog.ShowAsync() == ContentDialogResult.Primary;
    }

    public async Task<bool> ConfirmUpdateDownloadAsync(string version)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = I18n.Get("dialogs.updateTitle"),
            Content = I18n.Format("dialogs.updateBody", version),
            PrimaryButtonText = I18n.Get("dialogs.download"),
            CloseButtonText = I18n.Get("dialogs.later"),
            DefaultButton = ContentDialogButton.Primary,
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    private void OnAppWindowClosing(
        Microsoft.UI.Windowing.AppWindow sender,
        Microsoft.UI.Windowing.AppWindowClosingEventArgs args)
    {
        _ = sender;
        if (_allowClose || !_trayAvailable)
        {
            return;
        }

        args.Cancel = true;
        AppWindow.Hide();
    }

    private void OnNavigationSelectionChanged(
        NavigationView sender,
        NavigationViewSelectionChangedEventArgs args)
    {
        _ = sender;
        string tag = (args.SelectedItemContainer?.Tag as string) ?? "profile";
        if (!StringComparer.Ordinal.Equals(tag, _currentNavigationTag))
        {
            if (!_navigatingBack)
            {
                _navigationHistory.Push(_currentNavigationTag);
            }

            _currentNavigationTag = tag;
        }

        AppTitleBar.IsBackButtonEnabled = _navigationHistory.Count > 0;
        if (tag == "groups")
        {
            ViewModel.PrepareGroupsForPresentation();
        }

        HomePage.Visibility = tag == "profile" ? Visibility.Visible : Visibility.Collapsed;
        GroupsPage.Visibility = tag == "groups" ? Visibility.Visible : Visibility.Collapsed;
        StorePage.Visibility = tag == "store" ? Visibility.Visible : Visibility.Collapsed;
        SettingsPage.Visibility = tag == "settings" ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnTitleBarBackRequested(TitleBar sender, object args)
    {
        _ = sender;
        _ = args;
        if (_navigationHistory.Count == 0)
        {
            return;
        }

        string tag = _navigationHistory.Pop();
        NavigationViewItem? item = RootNavigation.MenuItems
            .OfType<NavigationViewItem>()
            .FirstOrDefault(candidate =>
                StringComparer.Ordinal.Equals(candidate.Tag as string, tag));
        if (item is null)
        {
            AppTitleBar.IsBackButtonEnabled = _navigationHistory.Count > 0;
            return;
        }

        _navigatingBack = true;
        try
        {
            RootNavigation.SelectedItem = item;
        }
        finally
        {
            _navigatingBack = false;
        }
    }

    private void OnTitleBarPaneToggleRequested(TitleBar sender, object args)
    {
        _ = sender;
        _ = args;
        RootNavigation.IsPaneOpen = !RootNavigation.IsPaneOpen;
    }

    private void OnNavigationPaneOpened(NavigationView sender, object args)
    {
        _ = sender;
        _ = args;
        ExpandedConnectionStatus.Visibility = Visibility.Visible;
        CompactConnectionDot.Visibility = Visibility.Collapsed;
    }

    private void OnNavigationPaneClosed(NavigationView sender, object args)
    {
        _ = sender;
        _ = args;
        ExpandedConnectionStatus.Visibility = Visibility.Collapsed;
        CompactConnectionDot.Visibility = Visibility.Visible;
    }

    private void OnCharacterSelectorLoaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateCharacterSelectorColumns();
    }

    private void OnCharacterSelectorSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateCharacterSelectorColumns();
    }

    private void UpdateCharacterSelectorColumns()
    {
        if (CharacterSelector.ItemsPanelRoot is not ItemsWrapGrid panel
            || CharacterSelector.ActualWidth <= 0)
        {
            return;
        }

        panel.ItemWidth = Math.Max(96, Math.Floor((CharacterSelector.ActualWidth - 24d) / 5d));
    }

    private void OnNoticeRaised(NoticeMessage notice)
    {
        _statusDismissTimer.Stop();
        StatusInfoBar.Message = notice.Message;
        StatusInfoBar.Severity = notice.Kind switch
        {
            NoticeKind.Success => InfoBarSeverity.Success,
            NoticeKind.Warning => InfoBarSeverity.Warning,
            NoticeKind.Error => InfoBarSeverity.Error,
            _ => InfoBarSeverity.Informational,
        };
        StatusInfoBar.IsOpen = true;
        if (notice.Kind is NoticeKind.Success or NoticeKind.Informational)
        {
            _statusDismissTimer.Start();
        }
    }

    private void OnStatusDismissTimerTick(object? sender, object args)
    {
        _ = sender;
        _ = args;
        _statusDismissTimer.Stop();
        StatusInfoBar.IsOpen = false;
    }

    private void ApplyBackdrop()
    {
        if (OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000)
            && MicaController.IsSupported())
        {
            SystemBackdrop = new MicaBackdrop { Kind = MicaKind.Base };
        }
    }

    private ResponsiveWindowSize ApplyResponsiveSize()
    {
        WindowsMonitorInfo monitor = WindowsMonitorService.Select(identifier: null);
        ResponsiveWindowSize size = ResponsiveWindowSizePolicy.Calculate(
            monitor,
            SideyWindowKind.Settings);
        ResponsiveWindowSize minimumWindowSize = ResponsiveWindowSizePolicy.Minimum(
            monitor,
            SideyWindowKind.Settings);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(size.Width, size.Height));
        AppWindow.Move(new Windows.Graphics.PointInt32(
            monitor.WorkAreaPixels.X + ((monitor.WorkAreaPixels.Width - size.Width) / 2),
            monitor.WorkAreaPixels.Y + ((monitor.WorkAreaPixels.Height - size.Height) / 2)));
        return minimumWindowSize;
    }

    private void OnWindowClosed(object sender, WindowEventArgs args)
    {
        _ = sender;
        _ = args;
        AppWindow.Closing -= OnAppWindowClosing;
        Closed -= OnWindowClosed;
        ViewModel.NoticeRaised -= OnNoticeRaised;
        _minimumSizeController.Dispose();
        _statusDismissTimer.Stop();
        _statusDismissTimer.Tick -= OnStatusDismissTimerTick;
#if DEBUG
        _validationMetricsTimer.Stop();
        _validationMetricsTimer.Tick -= OnValidationMetricsTimerTick;
#endif
    }

#if DEBUG
    private void OnValidationMetricsTimerTick(object? sender, object args)
    {
        _ = sender;
        _ = args;
        ViewModel.RefreshDiagnostics();
    }
#endif
}
