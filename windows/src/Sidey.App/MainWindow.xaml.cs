using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Media.Imaging;
using Sidey.App.Controls;
using Sidey.Core.Localization;
using Sidey.Platform.Windows;
using Sidey.Presentation.Services;
using Sidey.Presentation.ViewModels;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;
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
    private readonly IMainWindowCoordinator _coordinator;
    private readonly WindowsFeedbackWindowMonitor? _feedbackMonitor;
    private StorePreviewStage? _activePreview;

    public MainWindow(
        IMainWindowCoordinator coordinator,
        IUpdateService updateService)
    {
        InitializeComponent();
        _coordinator = coordinator;
        AppTitleBar.IconSource = new ImageIconSource
        {
            ImageSource = new BitmapImage(new Uri(Path.Combine(
                SideyDeploymentPaths.DeploymentRoot(), "Assets", "Icons", "SideyAppIcon-20.png"))),
        };
        ViewModel = new MainWindowViewModel(coordinator, this, updateService);
        CharacterSoundVolumeSlider.AdjustmentCompleted += () =>
        {
            ViewModel.CharacterSoundEffectsVolume = CharacterSoundVolumeSlider.Value;
            ViewModel.CompleteSoundVolumeAdjustment();
        };
        CharacterSoundVolumeSlider.AdjustmentCanceled += ViewModel.StopSoundVolumeFeedback;
        if (coordinator is AppCoordinator appCoordinator)
            appCoordinator.AnimationsChanged += OnAnimationsChanged;
        try
        {
            _feedbackMonitor = new WindowsFeedbackWindowMonitor(WinRT.Interop.WindowNative.GetWindowHandle(this),
                () => coordinator.StopImpactSounds(), async () =>
                {
                    try
                    { await coordinator.RetryConnectionAsync(userInitiated: false); }
                    catch (Exception exception) { StartupDiagnostics.NonFatal("resume-connection", exception); }
                });
        }
        catch (Exception exception) { StartupDiagnostics.NonFatal("feedback-system-notifications", exception); }
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

    private void OnAnimationsChanged()
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (_isClosed)
                return;
            ViewModel.RefreshFeedbackPresentation();
            _activePreview?.SetAnimationsEnabled(_coordinator.AnimationsEnabled);
        });
    }

    public bool ShouldExitOnClose => _allowClose || !_trayAvailable;

    internal async Task VerifyExternalAssetsSmokeAsync()
    {
        Activate();
        var image = (BitmapImage)((ImageIconSource)AppTitleBar.IconSource).ImageSource;
        StorageFile iconFile = await Windows.Storage.StorageFile.GetFileFromPathAsync(image.UriSource.LocalPath);
        using IRandomAccessStreamWithContentType iconStream = await iconFile.OpenReadAsync();
        BitmapDecoder decoder = await Windows.Graphics.Imaging.BitmapDecoder.CreateAsync(iconStream);
        if (decoder.PixelWidth != 20 || decoder.PixelHeight != 20)
        {
            throw new InvalidOperationException("The external title bar icon file is not 20x20.");
        }
        DateTimeOffset deadline = DateTimeOffset.UtcNow.AddSeconds(5);
        while (image.PixelWidth == 0 && DateTimeOffset.UtcNow < deadline)
        {
            await Task.Delay(25);
        }
        // XAML may decode the displayed icon at its rendered size for the current DPI.
        // Validate the source dimensions above and successful UI decoding separately.
        StartupDiagnostics.Stage($"external-assets-smoke-decoded width={image.PixelWidth} height={image.PixelHeight}");
        if (image.PixelWidth <= 0 || image.PixelHeight <= 0)
        {
            throw new InvalidOperationException("The external title bar icon did not decode for display.");
        }
        StartupDiagnostics.Stage("external-assets-smoke-complete titlebar-icon=20x20");
    }

    internal async Task VerifySoundControlsSmokeAsync()
    {
        ShowPage("settings");
        await Task.Delay(60);
        if (CharacterSoundVolumeSlider.CompletionThumbCount == 0)
            throw new InvalidOperationException("Sound controls smoke: slider Thumb completion is not connected.");
        int originalVolume = _coordinator.State.Preferences.CharacterSoundEffectsVolume;
        bool originalEnabled = _coordinator.State.Preferences.CharacterSoundEffectsEnabled;
        try
        {
            CharacterSoundVolumeSlider.Value = 37;
            DateTimeOffset deadline = DateTimeOffset.UtcNow.AddSeconds(2);
            while (ViewModel.CharacterSoundEffectsVolume != 37 && DateTimeOffset.UtcNow < deadline)
                await Task.Delay(10);
            await ViewModel.FlushSoundSettingsAsync();
            if (_coordinator.State.Preferences.CharacterSoundEffectsVolume != 37
                || ViewModel.CharacterSoundVolumeLabel != "37%")
            {
                StartupDiagnostics.Stage($"sound-controls-failed slider={CharacterSoundVolumeSlider.Value} model={ViewModel.CharacterSoundEffectsVolume} saved={_coordinator.State.Preferences.CharacterSoundEffectsVolume}");
                throw new InvalidOperationException("Sound controls smoke: slider did not save its value.");
            }
            ViewModel.CompleteSoundVolumeAdjustment();
            await ExportSoundCardSmokeAsync("enabled");
            SoundMuteButton.Command.Execute(null);
            await ViewModel.FlushSoundSettingsAsync();
            if (ViewModel.CharacterSoundEffectsEnabled || ViewModel.CharacterSoundEffectsVolume != 37)
                throw new InvalidOperationException("Sound controls smoke: mute button lost volume or did not mute.");
            await ExportSoundCardSmokeAsync("muted");
            SoundMuteButton.Command.Execute(null);
            await ViewModel.FlushSoundSettingsAsync();
            if (!ViewModel.CharacterSoundEffectsEnabled || ViewModel.CharacterSoundEffectsVolume != 37)
                throw new InvalidOperationException("Sound controls smoke: unmute button failed.");
            CharacterSoundVolumeSlider.Value = 0;
            await Task.Delay(30);
            await ViewModel.FlushSoundSettingsAsync();
            if (ViewModel.CharacterSoundEffectsEnabled || !CharacterSoundVolumeSlider.IsEnabled)
                throw new InvalidOperationException("Sound controls smoke: zero volume did not mute or slider was disabled.");
            CharacterSoundVolumeSlider.Value = 25;
            await Task.Delay(30);
            await ViewModel.FlushSoundSettingsAsync();
            if (!ViewModel.CharacterSoundEffectsEnabled || !_coordinator.State.Preferences.CharacterSoundEffectsEnabled)
                throw new InvalidOperationException("Sound controls smoke: positive volume did not enable sound.");
            ViewModel.CompleteSoundVolumeAdjustment();
            StartupDiagnostics.Stage("sound-controls-smoke-complete slider=0,25,37 mute-button=true");
        }
        finally
        {
            ViewModel.StopSoundVolumeFeedback();
            await _coordinator.SaveCharacterSoundEffectsAsync(originalEnabled, originalVolume);
            _coordinator.ApplyCharacterSoundEffects(originalEnabled, originalVolume);
            ViewModel.ApplyState(_coordinator.State);
        }
    }

    private async Task ExportSoundCardSmokeAsync(string state)
    {
        string? root = Environment.GetEnvironmentVariable("SIDEY_STARTUP_SMOKE_DATA_ROOT");
        if (string.IsNullOrEmpty(root))
            return;
        var rendered = new RenderTargetBitmap();
        await rendered.RenderAsync(SoundSettingsCard);
        using var stream = new Windows.Storage.Streams.InMemoryRandomAccessStream();
        BitmapEncoder encoder = await Windows.Graphics.Imaging.BitmapEncoder.CreateAsync(Windows.Graphics.Imaging.BitmapEncoder.PngEncoderId, stream);
        IBuffer buffer = await rendered.GetPixelsAsync();
        byte[] pixels = System.Runtime.InteropServices.WindowsRuntime.WindowsRuntimeBufferExtensions.ToArray(buffer);
        encoder.SetPixelData(Windows.Graphics.Imaging.BitmapPixelFormat.Bgra8,
            Windows.Graphics.Imaging.BitmapAlphaMode.Premultiplied, (uint)rendered.PixelWidth, (uint)rendered.PixelHeight, 96, 96, pixels);
        await encoder.FlushAsync();
        stream.Seek(0);
        using var reader = new Windows.Storage.Streams.DataReader(stream);
        await reader.LoadAsync((uint)stream.Size);
        byte[] png = new byte[(int)stream.Size];
        reader.ReadBytes(png);
        await File.WriteAllBytesAsync(Path.Combine(root, $"sound-settings-{state}.png"), png);
    }

    internal async Task VerifyLiveLanguageSmokeAsync()
    {
        ShowPage("settings");
        ViewModel.Nickname = "draft";
        ViewModel.InviteCode = "ABCDEF";
        ViewModel.CreateRoomName = "room draft";
        CharacterSelectionItemViewModel characterItem = ViewModel.CharacterSelections[0];
        CosmeticSelectionItemViewModel bubbleItem = ViewModel.BubbleSelections[0];
        StoreProductPreviewViewModel productItem = ViewModel.StoreProducts[0];
        nint handle = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var composer = new ComposerWindow(new ComposerViewModel());
        try
        {
            composer.Activate();
            composer.ViewModel.Draft = "language draft";
            var input = (TextBox)((FrameworkElement)composer.Content).FindName("MessageInput");
            await Task.Delay(100);
            for (int repeat = 0; repeat < 2; repeat++)
            {
                foreach ((string? language, int index) in new[]
                {
                    ("en-US", 1), ("ja-JP", 2), ("zh-CN", 3), ("zh-TW", 4),
                    ("uk-UA", 5), ("ru-RU", 6), ("ko-KR", 0),
                })
                {
                    LanguageComboBox.SelectedIndex = index;
                    DateTimeOffset deadline = DateTimeOffset.UtcNow.AddSeconds(4);
                    while ((I18n.Language != language || !ViewModel.IsLanguageSelectionEnabled)
                           && DateTimeOffset.UtcNow < deadline)
                        await Task.Delay(25);
                    await Task.Delay(40);
                    if (I18n.Language != language
                        || LanguageDescriptionText.Text != I18n.Get("settings.languageDescription")
                        || ((NavigationViewItem)RootNavigation.MenuItems[0]).Content as string != I18n.Get("navigation.profile")
                        || characterItem.DisplayName != Sidey.Core.Domain.PixelCharacterCatalog.Get(characterItem.Id).DisplayName
                        || bubbleItem.DisplayName != I18n.Get("profile.defaultBubble")
                        || !ReferenceEquals(productItem, ViewModel.StoreProducts[0]))
                    {
                        StartupDiagnostics.Stage($"live-language-smoke-failed expected={language} actual={I18n.Language} selected={LanguageComboBox.SelectedIndex} model={ViewModel.SelectedLanguageIndex} enabled={ViewModel.IsLanguageSelectionEnabled} text={LanguageDescriptionText.Text == I18n.Get("settings.languageDescription")}");
                        throw new InvalidOperationException("Live language smoke: text or selection did not update in place.");
                    }
                    if (handle != WinRT.Interop.WindowNative.GetWindowHandle(this)
                        || ViewModel.Nickname != "draft" || ViewModel.InviteCode != "ABCDEF"
                        || ViewModel.CreateRoomName != "room draft" || composer.ViewModel.Draft != "language draft"
                        || input.PlaceholderText != I18n.Get("composer.placeholder"))
                        throw new InvalidOperationException("Live language smoke: window or draft was replaced.");
                }
            }
        }
        finally { composer.Close(); }
        StartupDiagnostics.Stage("live-language-smoke-complete changes=6 drafts-preserved=true");
    }

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
            _activePreview = previewStage;
            previewStage.SetAnimationsEnabled(_coordinator.AnimationsEnabled);
            previewStage.CharacterImpact += _coordinator.PlayImpactSound;
            previewStage.StopSounds += scope => _coordinator.StopImpactSounds(scope);
            if (ActiveXamlRoot() is not { } xamlRoot)
            {
                return;
            }

            content.Children.Add(previewStage);
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
            _activePreview = null;
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
        ViewModel.StopSoundVolumeFeedback();
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
        ViewModel.StopSoundVolumeFeedback();
        _lifetime.Cancel();
        MainRoot.DataContext = null;
    }

    private void OnNavigationSelectionChanged(
        NavigationView sender,
        NavigationViewSelectionChangedEventArgs args)
    {
        _ = sender;
        string tag = (args.SelectedItemContainer?.Tag as string) ?? "profile";
        if (tag != "settings")
            ViewModel.StopSoundVolumeFeedback();
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
        _feedbackMonitor?.Dispose();
        if (_coordinator is AppCoordinator appCoordinator)
            appCoordinator.AnimationsChanged -= OnAnimationsChanged;
        _activePreview?.EndPresentation();
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
