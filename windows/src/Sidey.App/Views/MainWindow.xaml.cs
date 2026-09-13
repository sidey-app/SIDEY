using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Media.Imaging;
using Sidey.App.Controls;
using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Sidey.Platform.Windows;
using Sidey.Presentation.Services;
using Sidey.Presentation.ViewModels;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;
using Windows.UI.ViewManagement;

namespace Sidey.App.Views;

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
    private bool _storeSearchUpdateQueued;
    private bool _storePreviewDialogOpen;
    private TaskCompletionSource? _storePreviewClosed;
    private Task _storeFilterTransition = Task.CompletedTask;
    private readonly HashSet<Guid> _roomExpansionAnimations = [];
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
        ViewModel.PropertyChanged += OnViewModelPropertyChanged;
        ApplyRequestedTheme();
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

    private void OnViewModelPropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs args)
    {
        _ = sender;
        if (args.PropertyName == nameof(MainWindowViewModel.SelectedThemeIndex))
            ApplyRequestedTheme();
    }

    private void ApplyRequestedTheme()
    {
        SideyWindowTheme.Apply(
            MainRoot,
            (AppThemePreference)ViewModel.SelectedThemeIndex);
    }

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
        DateTimeOffset deadline = DateTimeOffset.UtcNow.AddSeconds(15);
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

    internal void VerifyLocalCatalogLoadingSmoke()
    {
        if (!ViewModel.IsRemoteContentLoading
            || CharacterSelector.Visibility != Visibility.Visible
            || BubbleSelector.Visibility != Visibility.Visible
            || ThrowableSelector.Visibility != Visibility.Visible
            || !ViewModel.CharacterSelections.Select(character => character.Id)
                .SequenceEqual(
                    PixelCharacterCatalog.Selectable.Select(character => character.Id),
                    StringComparer.Ordinal)
            || ViewModel.BubbleSelections.Count != 1
            || ViewModel.ThrowableSelections.Count != 1)
        {
            throw new InvalidOperationException(
                "Local catalog smoke: default selections were hidden during remote loading.");
        }

        string cachedCharacterId = PixelCharacterCatalog.NormalizeId(
            _coordinator.State.Preferences.CachedCharacterId);
        bool cachedCharacterIsFree = PixelCharacterCatalog.Selectable.Any(character =>
            StringComparer.Ordinal.Equals(character.Id, cachedCharacterId));
        CharacterSelectionItemViewModel[] selectedCharacters = [.. ViewModel.CharacterSelections.Where(
            character => character.IsSelected)];
        if (cachedCharacterIsFree
            ? selectedCharacters.Length != 1
                || !StringComparer.Ordinal.Equals(selectedCharacters[0].Id, cachedCharacterId)
            : selectedCharacters.Length != 0)
        {
            throw new InvalidOperationException(
                "Local catalog smoke: cached character selection was guessed incorrectly.");
        }

        StartupDiagnostics.Stage("local-catalog-loading-smoke-complete");
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
        ShowPage("about");
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

    internal async Task VerifyStoreFilterToggleSmokeAsync()
    {
        string originalSearchText = ViewModel.StoreSearchText;
        try
        {
            ShowPage("store");
            StoreFilterToggle.IsChecked = false;
            SetStoreFilterPanelExpanded(false);
            StoreFilterToggle.UpdateLayout();
            ContentPresenter? filterPresenter = FindNamedDescendant<ContentPresenter>(
                StoreFilterToggle,
                "FilterTogglePresenter");
            if (filterPresenter is null
                || !IsTransparentBrush(filterPresenter.Background)
                || filterPresenter.BorderThickness.Left != 0
                || StoreResetFiltersButton.BorderThickness.Left == 0)
            {
                throw new InvalidOperationException(
                    "Store filter smoke: closed and reset button surfaces are incorrect.");
            }

            StoreFilterToggle.IsChecked = true;
            OnStoreFilterToggleClick(StoreFilterToggle, new RoutedEventArgs());
            await _storeFilterTransition;
            if (StoreFilterPanel.Visibility != Visibility.Visible)
            {
                throw new InvalidOperationException("Store filter smoke: panel did not open.");
            }
            if (StoreFilterChevron.RenderTransform is not RotateTransform { Angle: 180 })
            {
                throw new InvalidOperationException("Store filter smoke: chevron did not rotate open.");
            }
            if (IsTransparentBrush(filterPresenter.Background)
                || filterPresenter.BorderThickness.Left == 0)
            {
                throw new InvalidOperationException(
                    "Store filter smoke: open filter did not use a neutral surface.");
            }

            await WaitForLoadedAsync(StoreSearchTextBox);
            if (!StoreSearchTextBox.Focus(FocusState.Programmatic))
            {
                throw new InvalidOperationException("Store filter smoke: search input did not receive focus.");
            }

            StoreSearchTextBox.Text = "c";
            QueueStoreSearchUpdate();
            StoreSearchTextBox.Text = "ca";
            QueueStoreSearchUpdate();
            StoreSearchTextBox.Text = "cat";
            QueueStoreSearchUpdate();
            await WaitForDispatcherTurnAsync();
            if (!StringComparer.Ordinal.Equals(ViewModel.StoreSearchText, "cat")
                || StoreFilterPanel.Visibility != Visibility.Visible)
            {
                throw new InvalidOperationException(
                    "Store filter smoke: rapid search input did not apply while the panel remained open.");
            }

            ViewModel.SelectedStoreSortIndex = 2;
            ViewModel.HidesOwnedStoreProducts = true;
            OnResetStoreFiltersClick(StoreResetFiltersButton, new RoutedEventArgs());
            if (StoreSearchTextBox.Text.Length != 0
                || ViewModel.StoreSearchText.Length != 0
                || ViewModel.SelectedStoreKindIndex != 0
                || ViewModel.SelectedStoreSortIndex != 0
                || ViewModel.HidesOwnedStoreProducts)
            {
                throw new InvalidOperationException("Store filter smoke: reset did not restore defaults.");
            }
            StoreSearchTextBox.Text = "cat";
            QueueStoreSearchUpdate();
            await WaitForDispatcherTurnAsync();

            StoreFilterToggle.IsChecked = false;
            OnStoreFilterToggleClick(StoreFilterToggle, new RoutedEventArgs());
            await _storeFilterTransition;
            if (StoreFilterPanel.Visibility != Visibility.Collapsed
                || !StringComparer.Ordinal.Equals(StoreSearchTextBox.Text, "cat")
                || !StringComparer.Ordinal.Equals(ViewModel.StoreSearchText, "cat")
                || StoreFilterChevron.RenderTransform is not RotateTransform { Angle: 0 })
            {
                StartupDiagnostics.Stage(
                    $"store-filter-toggle-smoke-failed visibility={StoreFilterPanel.Visibility} query-retained={StringComparer.Ordinal.Equals(StoreSearchTextBox.Text, "cat")} query-applied={StringComparer.Ordinal.Equals(ViewModel.StoreSearchText, "cat")}");
                throw new InvalidOperationException(
                    "Store filter smoke: focused search did not close while preserving its query.");
            }

            StartupDiagnostics.Stage(
                "store-filter-toggle-smoke-complete focused-search=true query-preserved=true");
        }
        finally
        {
            ViewModel.StoreSearchText = originalSearchText;
            StoreFilterToggle.IsChecked = false;
            SetStoreFilterPanelExpanded(false);
        }
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
        NavigationViewItem? item = FindNavigationItem(tag);
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

    public void ShowUpdatesAndCheck()
    {
        if (_isClosed)
        {
            return;
        }

        ShowPage("about");
        DispatcherQueue.TryEnqueue(() =>
        {
            if (_isClosed)
            {
                return;
            }

            AboutPage.UpdateLayout();
            UpdateSection.StartBringIntoView(new BringIntoViewOptions
            {
                AnimationDesired = _coordinator.AnimationsEnabled,
                VerticalAlignmentRatio = 0,
            });
        });

        if (ViewModel.CheckForUpdatesCommand.CanExecute(null))
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
            if (ActiveXamlRoot() is null)
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
            StorePreviewContent.Content = content;
            StorePreviewActionButton.Content = product.IsOwned
                ? I18n.Get("store.owned")
                : I18n.Format("store.purchase", product.FormattedPrice);
            _storePreviewClosed = new TaskCompletionSource(
                TaskCreationOptions.RunContinuationsAsynchronously);
            AppTitleBar.IsEnabled = false;
            RootNavigation.IsEnabled = false;
            StorePreviewOverlay.Visibility = Visibility.Visible;
            previewStage.BeginPresentation();
            await WaitForLoadedAsync(StorePreviewCloseButton);
            StorePreviewCloseButton.Focus(FocusState.Programmatic);
            await _storePreviewClosed.Task;
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
            DismissStorePreview();
            previewStage?.EndPresentation();
            _activePreview = null;
            _storePreviewClosed = null;
            _storePreviewDialogOpen = false;
        }
    }

    internal async Task VerifyStorePreviewLightDismissSmokeAsync()
    {
        ShowPage("store");
        ViewModel.StoreProducts[0].PreviewCommand.Execute(null);
        DateTimeOffset deadline = DateTimeOffset.UtcNow.AddSeconds(5);
        while (StorePreviewOverlay.Visibility != Visibility.Visible
            && DateTimeOffset.UtcNow < deadline)
        {
            await Task.Delay(10);
        }

        if (StorePreviewOverlay.Visibility != Visibility.Visible
            || StorePreviewContent.Content is null
            || RootNavigation.IsEnabled)
        {
            throw new InvalidOperationException(
                "Store preview smoke: the light-dismiss overlay did not open.");
        }

        DismissStorePreview();
        while (_storePreviewDialogOpen && DateTimeOffset.UtcNow < deadline)
        {
            await Task.Delay(10);
        }

        if (_storePreviewDialogOpen
            || StorePreviewOverlay.Visibility != Visibility.Collapsed
            || StorePreviewContent.Content is not null
            || !RootNavigation.IsEnabled)
        {
            throw new InvalidOperationException(
                "Store preview smoke: outside dismissal did not release the preview.");
        }

        StartupDiagnostics.Stage("store-preview-light-dismiss-smoke-complete");
    }

    private void OnStorePreviewOverlayTapped(object sender, TappedRoutedEventArgs args)
    {
        _ = sender;
        args.Handled = true;
        DismissStorePreview();
    }

    private void OnStorePreviewSurfaceTapped(object sender, TappedRoutedEventArgs args)
    {
        _ = sender;
        args.Handled = true;
    }

    private void OnStorePreviewCloseClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        DismissStorePreview();
    }

    private void OnStorePreviewSurfaceKeyDown(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        if (args.Key != Windows.System.VirtualKey.Escape)
        {
            return;
        }

        args.Handled = true;
        DismissStorePreview();
    }

    private void DismissStorePreview()
    {
        _activePreview?.EndPresentation();
        StorePreviewOverlay.Visibility = Visibility.Collapsed;
        StorePreviewContent.Content = null;
        AppTitleBar.IsEnabled = true;
        RootNavigation.IsEnabled = true;
        _storePreviewClosed?.TrySetResult();
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
        DismissStorePreview();
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
        AboutPage.Visibility = tag == "about" ? Visibility.Visible : Visibility.Collapsed;
        if (navigationChanged)
        {
            ScrollViewer selectedPage = tag switch
            {
                "groups" => GroupsPage,
                "store" => StorePage,
                "settings" => SettingsPage,
                "about" => AboutPage,
                _ => HomePage,
            };
            selectedPage.ChangeView(null, 0, null, disableAnimation: true);
            DispatcherQueue.TryEnqueue(() =>
                selectedPage.ChangeView(null, 0, null, disableAnimation: true));
            AnimatePageRefresh(selectedPage);
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

    private async void OnRoomHeaderTapped(object sender, TappedRoutedEventArgs args)
    {
        if (sender is not Grid header
            || header.DataContext is not RoomCardViewModel room
            || header.Tag is not FrameworkElement body
            || args.OriginalSource is DependencyObject source && HasButtonAncestor(source, header)
            || !_roomExpansionAnimations.Add(room.Room.Id))
        {
            return;
        }

        args.Handled = true;
        FontIcon? chevron = FindNamedDescendant<FontIcon>(header, "RoomExpansionChevron");
        try
        {
            if (!_coordinator.AnimationsEnabled)
            {
                room.ToggleCommand.Execute(null);
                SetChevronAngle(chevron, room.IsExpanded ? 180 : 0);
                return;
            }

            if (room.IsExpanded)
            {
                await Task.WhenAll(
                    AnimateRoomBodyAsync(body, expanding: false),
                    AnimateChevronAsync(chevron, expanding: false));
                room.ToggleCommand.Execute(null);
                body.Height = double.NaN;
                body.Opacity = 1;
            }
            else
            {
                room.ToggleCommand.Execute(null);
                body.Height = double.NaN;
                body.UpdateLayout();
                await Task.WhenAll(
                    AnimateRoomBodyAsync(body, expanding: true),
                    AnimateChevronAsync(chevron, expanding: true));
                body.Height = double.NaN;
                body.Opacity = 1;
            }
        }
        finally
        {
            _roomExpansionAnimations.Remove(room.Room.Id);
        }
    }

    private void OnRoomExpansionChevronLoaded(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is FontIcon chevron && chevron.DataContext is RoomCardViewModel room)
        {
            SetChevronAngle(chevron, room.IsExpanded ? 180 : 0);
        }
    }

    private void OnRoomHeaderPointerEntered(object sender, PointerRoutedEventArgs args)
    {
        _ = args;
        SetRoomHeaderHoverOpacity(sender, 1);
    }

    private void OnRoomHeaderPointerExited(object sender, PointerRoutedEventArgs args)
    {
        _ = args;
        SetRoomHeaderHoverOpacity(sender, 0);
    }

    private static void SetRoomHeaderHoverOpacity(object sender, double opacity)
    {
        if (sender is Grid header
            && header.Children
                .OfType<Border>()
                .FirstOrDefault(child => child.Name == "RoomHeaderHoverBackground") is { } hoverBackground)
        {
            hoverBackground.Opacity = opacity;
        }
    }

    private static bool HasButtonAncestor(DependencyObject source, DependencyObject boundary)
    {
        for (DependencyObject? current = source;
             current is not null && !ReferenceEquals(current, boundary);
             current = VisualTreeHelper.GetParent(current))
        {
            if (current is Button)
                return true;
        }

        return false;
    }

    private static T? FindNamedDescendant<T>(DependencyObject parent, string name)
        where T : FrameworkElement
    {
        int childCount = VisualTreeHelper.GetChildrenCount(parent);
        for (int index = 0; index < childCount; index++)
        {
            DependencyObject child = VisualTreeHelper.GetChild(parent, index);
            if (child is T element && StringComparer.Ordinal.Equals(element.Name, name))
            {
                return element;
            }

            if (FindNamedDescendant<T>(child, name) is { } descendant)
            {
                return descendant;
            }
        }

        return null;
    }

    private static bool IsTransparentBrush(Brush? brush) =>
        brush is null
        || brush.Opacity <= 0
        || brush is SolidColorBrush { Color.A: 0 };

    private static Task AnimateChevronAsync(FontIcon? chevron, bool expanding)
    {
        if (chevron is null)
        {
            return Task.CompletedTask;
        }

        SetChevronAngle(chevron, expanding ? 0 : 180);
        var angle = new DoubleAnimation
        {
            From = expanding ? 0 : 180,
            To = expanding ? 180 : 0,
            Duration = TimeSpan.FromMilliseconds(180),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut },
            EnableDependentAnimation = true,
        };
        Storyboard.SetTarget(angle, chevron);
        Storyboard.SetTargetProperty(
            angle,
            "(UIElement.RenderTransform).(RotateTransform.Angle)");

        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var storyboard = new Storyboard();
        storyboard.Children.Add(angle);
        storyboard.Completed += (_, _) => completion.TrySetResult();
        storyboard.Begin();
        return completion.Task;
    }

    private static void SetChevronAngle(FontIcon? chevron, double angle)
    {
        if (chevron?.RenderTransform is RotateTransform transform)
        {
            transform.Angle = angle;
        }
    }

    private static Task AnimateRoomBodyAsync(FrameworkElement body, bool expanding)
    {
        double expandedHeight = Math.Max(1, body.ActualHeight);
        body.Height = expanding ? 0 : expandedHeight;
        body.Opacity = expanding ? 0 : 1;
        if (body.RenderTransform is not TranslateTransform transform)
        {
            transform = new TranslateTransform();
            body.RenderTransform = transform;
        }
        transform.Y = expanding ? -8 : 0;

        var duration = new Duration(TimeSpan.FromMilliseconds(expanding ? 180 : 150));
        var easing = new CubicEase { EasingMode = EasingMode.EaseInOut };
        var height = new DoubleAnimation
        {
            From = expanding ? 0 : expandedHeight,
            To = expanding ? expandedHeight : 0,
            Duration = duration,
            EasingFunction = easing,
            EnableDependentAnimation = true,
        };
        Storyboard.SetTarget(height, body);
        Storyboard.SetTargetProperty(height, "Height");

        var opacity = new DoubleAnimation
        {
            From = expanding ? 0 : 1,
            To = expanding ? 1 : 0,
            Duration = duration,
            EasingFunction = easing,
        };
        Storyboard.SetTarget(opacity, body);
        Storyboard.SetTargetProperty(opacity, "Opacity");

        var translation = new DoubleAnimation
        {
            From = expanding ? -8 : 0,
            To = expanding ? 0 : -8,
            Duration = duration,
            EasingFunction = easing,
            EnableDependentAnimation = true,
        };
        Storyboard.SetTarget(translation, body);
        Storyboard.SetTargetProperty(
            translation,
            "(UIElement.RenderTransform).(TranslateTransform.Y)");

        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var storyboard = new Storyboard();
        storyboard.Children.Add(height);
        storyboard.Children.Add(opacity);
        storyboard.Children.Add(translation);
        storyboard.Completed += (_, _) => completion.TrySetResult();
        storyboard.Begin();
        return completion.Task;
    }

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
        NavigationViewItem? item = FindNavigationItem(tag);
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

    private NavigationViewItem? FindNavigationItem(string tag) =>
        RootNavigation.MenuItems
            .Concat(RootNavigation.FooterMenuItems)
            .OfType<NavigationViewItem>()
            .FirstOrDefault(candidate =>
                StringComparer.Ordinal.Equals(candidate.Tag as string, tag));

    private void OnStoreFilterToggleClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (!_storeFilterTransition.IsCompleted)
        {
            return;
        }

        _storeFilterTransition = TransitionStoreFilterPanelAsync(
            StoreFilterToggle.IsChecked == true);
    }

    private void OnStoreSearchTextChanged(object sender, TextChangedEventArgs args)
    {
        _ = args;
        if (sender is not TextBox)
        {
            return;
        }

        QueueStoreSearchUpdate();
    }

    private void QueueStoreSearchUpdate()
    {
        if (_storeSearchUpdateQueued)
        {
            return;
        }

        _storeSearchUpdateQueued = true;
        if (!DispatcherQueue.TryEnqueue(() =>
            {
                _storeSearchUpdateQueued = false;
                if (!_isClosed)
                {
                    ViewModel.StoreSearchText = StoreSearchTextBox.Text;
                }
            }))
        {
            _storeSearchUpdateQueued = false;
        }
    }

    private void OnResetStoreFiltersClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ViewModel.ResetStoreFiltersCommand.Execute(null);
        StoreSearchTextBox.Text = string.Empty;
        if (StoreKindSelector.Items.Count > 0)
        {
            StoreKindSelector.SelectedItem = StoreKindSelector.Items[0];
        }
    }

    private async Task TransitionStoreFilterPanelAsync(bool isExpanded)
    {
        StoreFilterToggle.IsEnabled = false;
        try
        {
            if (!isExpanded)
            {
                // Let TextBox focus and IME composition finish before hiding its visual tree.
                StoreFilterToggle.Focus(FocusState.Programmatic);
                await WaitForDispatcherTurnAsync();
            }

            if (!_coordinator.AnimationsEnabled)
            {
                SetStoreFilterPanelExpanded(isExpanded);
                return;
            }

            if (isExpanded)
            {
                StoreFilterPanel.Visibility = Visibility.Visible;
                StoreFilterPanel.Height = double.NaN;
                StoreFilterPanel.UpdateLayout();
            }

            await Task.WhenAll(
                AnimateFilterPanelAsync(StoreFilterPanel, isExpanded),
                AnimateChevronAsync(StoreFilterChevron, isExpanded));
            SetStoreFilterPanelExpanded(isExpanded);
        }
        finally
        {
            StoreFilterToggle.IsEnabled = true;
        }
    }

    private static Task AnimateFilterPanelAsync(FrameworkElement panel, bool expanding)
    {
        double expandedHeight = Math.Max(1, panel.ActualHeight);
        panel.Height = expanding ? 0 : expandedHeight;
        panel.Opacity = expanding ? 0 : 1;
        if (panel.RenderTransform is not TranslateTransform transform)
        {
            transform = new TranslateTransform();
            panel.RenderTransform = transform;
        }
        transform.Y = expanding ? -8 : 0;

        var duration = new Duration(TimeSpan.FromMilliseconds(180));
        var easing = new CubicEase { EasingMode = EasingMode.EaseInOut };
        var height = new DoubleAnimation
        {
            From = expanding ? 0 : expandedHeight,
            To = expanding ? expandedHeight : 0,
            Duration = duration,
            EasingFunction = easing,
            EnableDependentAnimation = true,
        };
        Storyboard.SetTarget(height, panel);
        Storyboard.SetTargetProperty(height, "Height");

        var opacity = new DoubleAnimation
        {
            From = expanding ? 0 : 1,
            To = expanding ? 1 : 0,
            Duration = duration,
            EasingFunction = easing,
        };
        Storyboard.SetTarget(opacity, panel);
        Storyboard.SetTargetProperty(opacity, "Opacity");

        var translation = new DoubleAnimation
        {
            From = expanding ? -8 : 0,
            To = expanding ? 0 : -8,
            Duration = duration,
            EasingFunction = easing,
            EnableDependentAnimation = true,
        };
        Storyboard.SetTarget(translation, panel);
        Storyboard.SetTargetProperty(
            translation,
            "(UIElement.RenderTransform).(TranslateTransform.Y)");

        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var storyboard = new Storyboard();
        storyboard.Children.Add(height);
        storyboard.Children.Add(opacity);
        storyboard.Children.Add(translation);
        storyboard.Completed += (_, _) => completion.TrySetResult();
        storyboard.Begin();
        return completion.Task;
    }

    private void SetStoreFilterPanelExpanded(bool isExpanded)
    {
        StoreFilterPanel.Visibility = isExpanded ? Visibility.Visible : Visibility.Collapsed;
        StoreFilterPanel.Height = double.NaN;
        StoreFilterPanel.Opacity = 1;
        if (StoreFilterPanel.RenderTransform is TranslateTransform transform)
        {
            transform.Y = 0;
        }
        SetChevronAngle(StoreFilterChevron, isExpanded ? 180 : 0);
    }

    private async Task WaitForDispatcherTurnAsync()
    {
        var completion = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        if (!DispatcherQueue.TryEnqueue(() => completion.TrySetResult()))
        {
            throw new InvalidOperationException("The UI dispatcher is unavailable.");
        }

        await completion.Task.WaitAsync(TimeSpan.FromSeconds(2));
    }

    private static async Task WaitForLoadedAsync(FrameworkElement element)
    {
        if (element.IsLoaded)
        {
            return;
        }

        var completion = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        RoutedEventHandler onLoaded = (_, _) => completion.TrySetResult();
        element.Loaded += onLoaded;
        try
        {
            await completion.Task.WaitAsync(TimeSpan.FromSeconds(2));
        }
        finally
        {
            element.Loaded -= onLoaded;
        }
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
        ViewModel.PropertyChanged -= OnViewModelPropertyChanged;
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
