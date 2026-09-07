using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Sidey.App.Controls;
using Sidey.Core.Localization;
using Sidey.Platform.Windows;
using Sidey.Presentation.Services;
using Sidey.Presentation.ViewModels;
using Windows.UI.ViewManagement;

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
    private bool _storePreviewDialogOpen;
    private bool _hideQueued;
    private bool _isClosed;
    private string _currentNavigationTag = "profile";
    private readonly Stack<string> _navigationHistory = new();
    private readonly WindowsMinimumSizeController _minimumSizeController;
    private readonly CancellationTokenSource _lifetime = new();

    public MainWindow(
        IMainWindowCoordinator coordinator,
        IUpdateService updateService)
    {
        InitializeComponent();
        ViewModel = new MainWindowViewModel(coordinator, this, updateService);
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
        ViewModel.StorePreviewRequested += OnStorePreviewRequested;
        _statusDismissTimer.Tick += OnStatusDismissTimerTick;
#if DEBUG
        _validationMetricsTimer.Tick += OnValidationMetricsTimerTick;
        _validationMetricsTimer.Start();
#endif
    }

    public MainWindowViewModel ViewModel { get; }

    public bool ShouldExitOnClose => _allowClose || !_trayAvailable;

    public void ApplyState(CoordinatorState state)
    {
        if (!_isClosed)
        {
            ViewModel.ApplyState(state);
        }
    }

    public void RefreshMonitors()
    {
        if (!_isClosed)
        {
            ViewModel.RefreshMonitors();
        }
    }

    public void ShowFatalError(Exception exception)
    {
        if (!_isClosed)
        {
            ViewModel.ReportError(exception);
        }
    }

    public void ShowPage(string tag)
    {
        if (_isClosed)
        {
            return;
        }

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
        if (_isClosed)
        {
            return;
        }

        _allowClose = true;
        Close();
    }

    public void SetTrayAvailable(bool available)
    {
        if (!_isClosed)
        {
            _trayAvailable = available;
        }
    }

    public void CheckForUpdates()
    {
        if (!_isClosed && ViewModel.CheckForUpdatesCommand.CanExecute(null))
        {
            ViewModel.CheckForUpdatesCommand.Execute(null);
        }
    }

    public async Task<bool> ConfirmInviteCodeRotationAsync()
    {
        if (ActiveXamlRoot() is not { } xamlRoot)
        {
            return false;
        }

        var dialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Title = I18n.Get("dialogs.rotateInviteTitle"),
            Content = I18n.Get("dialogs.rotateInviteBody"),
            PrimaryButtonText = I18n.Get("dialogs.rotateInvitePrimary"),
            CloseButtonText = I18n.Get("common.cancel"),
            DefaultButton = ContentDialogButton.Close,
        };
        try
        {
            return await dialog.ShowAsync() == ContentDialogResult.Primary;
        }
        catch (Exception) when (_isClosed)
        {
            return false;
        }
    }

    private async void OnStorePreviewRequested(StoreProductPreviewViewModel product)
    {
        if (_isClosed || _storePreviewDialogOpen)
        {
            return;
        }

        _storePreviewDialogOpen = true;
        StorePreviewStage? previewStage = null;
        try
        {
            var content = new StackPanel { Spacing = 12 };
            previewStage = new StorePreviewStage(
                product.Kind,
                product.CatalogItemId,
                product.CharacterId,
                _lifetime.Token);
            if (ActiveXamlRoot() is not { } xamlRoot)
            {
                return;
            }

            content.Children.Add(previewStage);
            if (product.Kind == Sidey.Core.Domain.CommerceProductKind.Character)
            {
                content.Children.Add(new TextBlock
                {
                    Text = I18n.Get("storePreview.characterHint"),
                    TextAlignment = TextAlignment.Center,
                    TextWrapping = TextWrapping.Wrap,
                });
            }
            content.Children.Add(new TextBlock
            {
                Text = product.DisplayName,
                FontSize = 22,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                TextAlignment = TextAlignment.Center,
                TextWrapping = TextWrapping.Wrap,
            });
            content.Children.Add(new TextBlock
            {
                Text = product.Description,
                Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources[
                    "TextFillColorSecondaryBrush"],
                TextAlignment = TextAlignment.Center,
                TextWrapping = TextWrapping.Wrap,
            });
            var dialog = new ContentDialog
            {
                XamlRoot = xamlRoot,
                Content = content,
                PrimaryButtonText = product.IsOwned
                    ? I18n.Get("store.owned")
                    : I18n.Format("store.purchase", product.FormattedPrice),
                IsPrimaryButtonEnabled = false,
                CloseButtonText = I18n.Get("common.close"),
                DefaultButton = ContentDialogButton.Close,
            };
            dialog.Closing += (_, _) => previewStage.EndPresentation();
            previewStage.BeginPresentation();
            await dialog.ShowAsync();
        }
        catch (OperationCanceledException) when (_lifetime.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            StartupDiagnostics.NonFatal("store-preview-dialog", exception);
            if (!_isClosed)
            {
                ViewModel.ReportError(exception);
            }
        }
        finally
        {
            previewStage?.EndPresentation();
            _storePreviewDialogOpen = false;
        }
    }

    public async Task<string?> PromptForRoomNameAsync(string currentName)
    {
        if (ActiveXamlRoot() is not { } xamlRoot)
        {
            return null;
        }

        var input = new TextBox
        {
            Text = currentName,
            MaxLength = 20,
            PlaceholderText = I18n.Get("dialogs.roomNamePlaceholder"),
        };
        var dialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Title = I18n.Get("groups.renameDialogTitle"),
            Content = input,
            PrimaryButtonText = I18n.Get("common.save"),
            CloseButtonText = I18n.Get("common.cancel"),
            DefaultButton = ContentDialogButton.Primary,
        };
        try
        {
            return await dialog.ShowAsync() == ContentDialogResult.Primary
                ? input.Text
                : null;
        }
        catch (Exception) when (_isClosed)
        {
            return null;
        }
    }

    public async Task<bool> ConfirmMemberRemovalAsync(string nickname)
    {
        if (ActiveXamlRoot() is not { } xamlRoot)
        {
            return false;
        }

        var dialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Title = I18n.Format("dialogs.removeMemberTitle", nickname),
            Content = I18n.Format("dialogs.removeMemberBody", nickname),
            PrimaryButtonText = I18n.Get("dialogs.removeMemberPrimary"),
            CloseButtonText = I18n.Get("common.cancel"),
            DefaultButton = ContentDialogButton.Close,
        };
        try
        {
            return await dialog.ShowAsync() == ContentDialogResult.Primary;
        }
        catch (Exception) when (_isClosed)
        {
            return false;
        }
    }

    public async Task<bool> ConfirmRoomLeaveAsync(string roomName, bool isOwner)
    {
        if (ActiveXamlRoot() is not { } xamlRoot)
        {
            return false;
        }

        var dialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Title = I18n.Format("dialogs.leaveRoomTitle", roomName),
            Content = I18n.Get(isOwner
                ? "dialogs.leaveOwnedRoomBody"
                : "dialogs.leaveRoomBody"),
            PrimaryButtonText = I18n.Get("dialogs.leaveRoomPrimary"),
            CloseButtonText = I18n.Get("common.cancel"),
            DefaultButton = ContentDialogButton.Close,
        };
        try
        {
            return await dialog.ShowAsync() == ContentDialogResult.Primary;
        }
        catch (Exception) when (_isClosed)
        {
            return false;
        }
    }

    public async Task<bool> ConfirmRoomDeletionAsync(string roomName)
    {
        if (ActiveXamlRoot() is not { } xamlRoot)
        {
            return false;
        }

        var impactDialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Title = I18n.Format("dialogs.deleteRoomTitle", roomName),
            Content = I18n.Get("dialogs.deleteRoomBody"),
            PrimaryButtonText = I18n.Get("dialogs.deleteRoomContinue"),
            CloseButtonText = I18n.Get("common.cancel"),
            DefaultButton = ContentDialogButton.Close,
        };
        ContentDialogResult impactResult;
        try
        {
            impactResult = await impactDialog.ShowAsync();
        }
        catch (Exception) when (_isClosed)
        {
            return false;
        }
        if (impactResult != ContentDialogResult.Primary || _isClosed)
        {
            return false;
        }

        var finalDialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Title = I18n.Get("dialogs.deleteRoomFinalTitle"),
            Content = I18n.Format("dialogs.deleteRoomFinalBody", roomName),
            PrimaryButtonText = I18n.Get("common.delete"),
            CloseButtonText = I18n.Get("common.cancel"),
            DefaultButton = ContentDialogButton.Close,
        };
        try
        {
            return await finalDialog.ShowAsync() == ContentDialogResult.Primary;
        }
        catch (Exception) when (_isClosed)
        {
            return false;
        }
    }

    public async Task<bool> ConfirmUpdateDownloadAsync(string version)
    {
        if (ActiveXamlRoot() is not { } xamlRoot)
        {
            return false;
        }

        var dialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Title = I18n.Get("dialogs.updateTitle"),
            Content = I18n.Format("dialogs.updateBody", version),
            PrimaryButtonText = I18n.Get("dialogs.download"),
            CloseButtonText = I18n.Get("dialogs.later"),
            DefaultButton = ContentDialogButton.Primary,
        };
        try
        {
            return await dialog.ShowAsync() == ContentDialogResult.Primary;
        }
        catch (Exception) when (_isClosed)
        {
            return false;
        }
    }

    private XamlRoot? ActiveXamlRoot() => _isClosed ? null : Content.XamlRoot;

    private void OnAppWindowClosing(
        Microsoft.UI.Windowing.AppWindow sender,
        Microsoft.UI.Windowing.AppWindowClosingEventArgs args)
    {
        _ = sender;
        if (_allowClose || !_trayAvailable)
        {
            PrepareForClose();
            return;
        }

        args.Cancel = true;
        if (_hideQueued)
        {
            return;
        }

        _hideQueued = true;
        DispatcherQueue.TryEnqueue(() =>
        {
            _hideQueued = false;
            if (!_allowClose && !_isClosed)
            {
                AppWindow.Hide();
            }
        });
    }

    private void PrepareForClose()
    {
        if (_isClosed)
        {
            return;
        }

        _isClosed = true;
        _lifetime.Cancel();
        MainRoot.DataContext = null;
    }

    private void OnNavigationSelectionChanged(
        NavigationView sender,
        NavigationViewSelectionChangedEventArgs args)
    {
        _ = sender;
        string tag = (args.SelectedItemContainer?.Tag as string) ?? "profile";
        bool navigationChanged = !StringComparer.Ordinal.Equals(tag, _currentNavigationTag);
        if (navigationChanged)
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
        if (navigationChanged)
        {
            AnimatePageRefresh(tag switch
            {
                "groups" => GroupsPage,
                "store" => StorePage,
                "settings" => SettingsPage,
                _ => HomePage,
            });
        }
    }

    private void OnStoreKindSelectionChanged(
        SelectorBar sender,
        SelectorBarSelectionChangedEventArgs args)
    {
        _ = args;
        if (sender.SelectedItem is null
            || MainRoot.DataContext is not MainWindowViewModel viewModel)
        {
            return;
        }

        int selectedIndex = sender.Items.IndexOf(sender.SelectedItem);
        int previousIndex = viewModel.SelectedStoreKindIndex;
        if (selectedIndex < 0 || selectedIndex == previousIndex)
        {
            return;
        }

        viewModel.SelectedStoreKindIndex = selectedIndex;
        AnimateSiblingPage(
            StoreResultsHost,
            selectedIndex > previousIndex ? 24d : -24d);
    }

    private static void AnimatePageRefresh(FrameworkElement element) =>
        AnimateElement(element, horizontalOffset: 0, verticalOffset: 18, durationMilliseconds: 220);

    private static void AnimateSiblingPage(FrameworkElement element, double horizontalOffset) =>
        AnimateElement(element, horizontalOffset, verticalOffset: 0, durationMilliseconds: 180);

    private static void AnimateElement(
        FrameworkElement element,
        double horizontalOffset,
        double verticalOffset,
        int durationMilliseconds)
    {
        if (!new UISettings().AnimationsEnabled)
        {
            element.Opacity = 1;
            element.RenderTransform = new TranslateTransform();
            return;
        }

        var transform = new TranslateTransform();
        element.RenderTransform = transform;
        element.Opacity = 1;

        var duration = new Duration(TimeSpan.FromMilliseconds(durationMilliseconds));
        var easing = new CubicEase { EasingMode = EasingMode.EaseOut };
        var opacity = new DoubleAnimation
        {
            From = 0,
            To = 1,
            Duration = duration,
            EasingFunction = easing,
        };
        Storyboard.SetTarget(opacity, element);
        Storyboard.SetTargetProperty(opacity, "Opacity");

        var translation = new DoubleAnimation
        {
            From = horizontalOffset == 0 ? verticalOffset : horizontalOffset,
            To = 0,
            Duration = duration,
            EasingFunction = easing,
            EnableDependentAnimation = true,
        };
        Storyboard.SetTarget(translation, element);
        Storyboard.SetTargetProperty(
            translation,
            horizontalOffset == 0
                ? "(UIElement.RenderTransform).(TranslateTransform.Y)"
                : "(UIElement.RenderTransform).(TranslateTransform.X)");

        var storyboard = new Storyboard();
        storyboard.Children.Add(opacity);
        storyboard.Children.Add(translation);
        storyboard.Begin();
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

    private void OnNavigationPaneOpening(NavigationView sender, object args)
    {
        _ = sender;
        _ = args;
        ShowExpandedConnectionStatus();
    }

    private void OnNavigationPaneOpened(NavigationView sender, object args)
    {
        _ = sender;
        _ = args;
        ShowExpandedConnectionStatus();
    }

    private void OnNavigationPaneClosing(
        NavigationView sender,
        NavigationViewPaneClosingEventArgs args)
    {
        _ = sender;
        _ = args;
        ShowCompactConnectionStatus();
    }

    private void OnNavigationPaneClosed(NavigationView sender, object args)
    {
        _ = sender;
        _ = args;
        ShowCompactConnectionStatus();
    }

    private void ShowCompactConnectionStatus()
    {
        ConnectionStatusRoot.Width = RootNavigation.CompactPaneLength;
        ExpandedConnectionStatus.Opacity = 0;
        CompactConnectionStatus.Opacity = 1;
    }

    private void ShowExpandedConnectionStatus()
    {
        ConnectionStatusRoot.Width = RootNavigation.OpenPaneLength;
        CompactConnectionStatus.Opacity = 0;
        ExpandedConnectionStatus.Opacity = 1;
    }

    private void OnStoreFilterToggleClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        bool isExpanded = StoreFilterToggle.IsChecked == true;
        StoreFilterPanel.Visibility = isExpanded ? Visibility.Visible : Visibility.Collapsed;
        StoreFilterChevron.Glyph = isExpanded ? "\uE70E" : "\uE70D";
    }

    private void OnNoticeRaised(NoticeMessage notice)
    {
        if (_isClosed)
        {
            return;
        }

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
        if (!_isClosed)
        {
            StatusInfoBar.IsOpen = false;
        }
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
        PrepareForClose();
        AppWindow.Closing -= OnAppWindowClosing;
        Closed -= OnWindowClosed;
        ViewModel.NoticeRaised -= OnNoticeRaised;
        ViewModel.StorePreviewRequested -= OnStorePreviewRequested;
        _minimumSizeController.Dispose();
        _statusDismissTimer.Stop();
        _statusDismissTimer.Tick -= OnStatusDismissTimerTick;
#if DEBUG
        _validationMetricsTimer.Stop();
        _validationMetricsTimer.Tick -= OnValidationMetricsTimerTick;
#endif
        _lifetime.Dispose();
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
