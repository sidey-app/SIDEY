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
    private bool _enforcingMinimumSize;
    private ResponsiveWindowSize _minimumWindowSize;

    public MainWindow(AppCoordinator coordinator)
    {
        InitializeComponent();
        ViewModel = new MainWindowViewModel(coordinator, this, new WindowsUpdateServiceAdapter());
        MainRoot.DataContext = ViewModel;
        ViewModel.PrepareGroupsForPresentation();
        Title = "SIDEY";
        SideyWindowIcon.Apply(AppWindow);
        RootNavigation.SelectedItem = RootNavigation.MenuItems[0];
        ApplyResponsiveSize();
        ApplyBackdrop();
        AppWindow.Changed += OnAppWindowChanged;
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
        if (tag == "groups")
        {
            ViewModel.PrepareGroupsForPresentation();
        }

        HomePage.Visibility = tag == "profile" ? Visibility.Visible : Visibility.Collapsed;
        GroupsPage.Visibility = tag == "groups" ? Visibility.Visible : Visibility.Collapsed;
        StorePage.Visibility = tag == "store" ? Visibility.Visible : Visibility.Collapsed;
        SettingsPage.Visibility = tag == "settings" ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnNavigationPaneOpened(NavigationView sender, object args)
    {
        _ = sender;
        _ = args;
        CompactConnectionDot.Visibility = Visibility.Collapsed;
    }

    private void OnNavigationPaneClosed(NavigationView sender, object args)
    {
        _ = sender;
        _ = args;
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

    private void ApplyResponsiveSize()
    {
        WindowsMonitorInfo monitor = WindowsMonitorService.Select(identifier: null);
        ResponsiveWindowSize size = ResponsiveWindowSizePolicy.Calculate(
            monitor,
            SideyWindowKind.Settings);
        _minimumWindowSize = size;
        AppWindow.Resize(new Windows.Graphics.SizeInt32(size.Width, size.Height));
        AppWindow.Move(new Windows.Graphics.PointInt32(
            monitor.WorkAreaPixels.X + ((monitor.WorkAreaPixels.Width - size.Width) / 2),
            monitor.WorkAreaPixels.Y + ((monitor.WorkAreaPixels.Height - size.Height) / 2)));
    }

    private void OnAppWindowChanged(
        Microsoft.UI.Windowing.AppWindow sender,
        Microsoft.UI.Windowing.AppWindowChangedEventArgs args)
    {
        if (!args.DidSizeChange || _enforcingMinimumSize)
        {
            return;
        }

        int width = Math.Max(sender.Size.Width, _minimumWindowSize.Width);
        int height = Math.Max(sender.Size.Height, _minimumWindowSize.Height);
        if (width == sender.Size.Width && height == sender.Size.Height)
        {
            return;
        }

        _enforcingMinimumSize = true;
        try
        {
            sender.Resize(new Windows.Graphics.SizeInt32(width, height));
        }
        finally
        {
            _enforcingMinimumSize = false;
        }
    }

    private void OnWindowClosed(object sender, WindowEventArgs args)
    {
        _ = sender;
        _ = args;
        AppWindow.Changed -= OnAppWindowChanged;
        AppWindow.Closing -= OnAppWindowClosing;
        Closed -= OnWindowClosed;
        ViewModel.NoticeRaised -= OnNoticeRaised;
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
