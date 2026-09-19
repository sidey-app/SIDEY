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
        if (Microsoft.UI.Windowing.AppWindowTitleBar.IsCustomizationSupported())
        {
            ExtendsContentIntoTitleBar = true;
            SetTitleBar(AppTitleBar);
        }
        SideyWindowTheme.FollowTitleBarTheme(this, MainRoot);
        MainRoot.Loaded += OnResponsiveRootLoaded;
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
        ApplyStoreFilterToggleSurface(StoreFilterPanel.Visibility == Visibility.Visible);
    }

    private void OnAnimationsChanged()
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (_isClosed)
                return;
            ViewModel.RefreshFeedbackPresentation();
            _activePreview?.SetAnimationsEnabled(_coordinator.AnimationsEnabled);
            UpdateResponsiveAnimations(MainRoot);
        });
    }

    private void OnResponsiveRootLoaded(object sender, RoutedEventArgs args)
    {
        UpdateResponsiveState();
        UpdateResponsiveAnimations(MainRoot);
    }

    private void OnPageViewportSizeChanged(object sender, SizeChangedEventArgs args) => UpdateResponsiveState();

    private void UpdateResponsiveState()
    {
        if (_isClosed || _coordinator is null || PageViewport.ActualWidth <= 0)
        {
            return;
        }
        VisualStateManager.GoToState(MainRoot,
            PageViewport.ActualWidth < 680 ? "Narrow" : "Standard", _coordinator.AnimationsEnabled);
    }

    private void UpdateResponsiveAnimations(DependencyObject root)
    {
        if (ReferenceEquals(root, MainRoot))
        {
            FrameworkElement[] controls = [GroupCreateAction, GroupJoinAction, StoreFilterToggle,
                StoreSortStack, StoreHideOwnedCheckBox, SoundControlsGrid, EdgeComboBox,
                SpanComboBox, MonitorComboBox, LanguageComboBox, ThemeComboBox];
            foreach (FrameworkElement control in controls)
            {
                control.Transitions = _coordinator.AnimationsEnabled
                    ? [new RepositionThemeTransition { IsStaggeringEnabled = false }] : null;
            }
        }
        if (root is ResponsiveFormPanel form)
        {
            form.AnimationsEnabled = _coordinator.AnimationsEnabled;
        }
        if (root is ResponsiveSelectionPanel selection)
        {
            selection.AnimationsEnabled = _coordinator.AnimationsEnabled;
        }
        for (int index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            UpdateResponsiveAnimations(VisualTreeHelper.GetChild(root, index));
        }
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

    internal async Task VerifyStoreScrollingSmokeAsync()
    {
        bool wasLoading = ViewModel.IsStoreLoading;
        int originalKind = ViewModel.SelectedStoreKindIndex;
        double originalWidth = StorePage.Width;
        double originalHeight = StorePage.Height;
        StoreProductPreviewViewModel longNameProduct = ViewModel.StoreProducts.First(
            product => product.Kind == CommerceProductKind.Throwable);
        string originalName = longNameProduct.DisplayName;
        try
        {
            ShowPage("store");
            ViewModel.IsStoreLoading = false;
            ViewModel.SelectedStoreKindIndex = (int)CommerceProductKind.Throwable;
            longNameProduct.DisplayName = string.Concat(Enumerable.Repeat("긴 상품 이름 ", 12));
            StorePage.Height = 360;
            foreach (double width in new[] { 620d, 400d })
            {
                StorePage.Width = width;
                StorePage.ChangeView(null, 0, null, disableAnimation: true);
                StorePage.UpdateLayout();
                await WaitForNextFrameAsync();
                StorePage.UpdateLayout();
                double extent = StorePage.ExtentHeight;
                double bottom = StorePage.ScrollableHeight;
                IReadOnlyList<StoreProductPreviewViewModel> products = ViewModel.VisibleStoreProducts;
                if (products.Count < 2 || !products.Contains(longNameProduct))
                    throw new InvalidOperationException("Store scrolling smoke requires the unfiltered throwable catalog.");
                var positions = new Dictionary<int, Windows.Foundation.Point>();
                int steps = Math.Max(1, (int)Math.Ceiling(bottom / (StorePage.ViewportHeight * .75)));
                double[] offsets = [.. Enumerable.Range(0, steps + 1).Select(step => bottom * step / steps)];
                foreach (double requested in offsets.Concat(offsets.Reverse()).Concat([bottom + 224, 0]))
                {
                    double target = Math.Min(requested, bottom);
                    StorePage.ChangeView(null, requested, null, disableAnimation: true);
                    await WaitForNextFrameAsync();
                    await WaitForNextFrameAsync();
                    StorePage.UpdateLayout();
                    if (!ReferenceEquals(products, ViewModel.VisibleStoreProducts)
                        || Math.Abs(StorePage.ExtentHeight - extent) > 1
                        || Math.Abs(StorePage.VerticalOffset - target) > 1)
                    {
                        StartupDiagnostics.Stage($"store-scroll-unstable width={width} target={target} offset={StorePage.VerticalOffset} extent={StorePage.ExtentHeight} initial={extent} products={ViewModel.VisibleStoreProducts.Count} initial-products={products.Count}");
                        throw new InvalidOperationException("Store scrolling changed the content extent or jumped away from its requested position.");
                    }
                    var visibleCards = new List<Windows.Foundation.Rect>();
                    for (int index = 0; index < products.Count; index++)
                    {
                        if (StoreProductRepeater.TryGetElement(index) is not FrameworkElement card)
                            continue;
                        Windows.Foundation.Rect visibleBounds = card.TransformToVisual(StorePage).TransformBounds(
                            new Windows.Foundation.Rect(0, 0, card.ActualWidth, card.ActualHeight));
                        if (visibleBounds.Bottom <= 0 || visibleBounds.Top >= StorePage.ViewportHeight)
                            continue;
                        if (visibleCards.Any(bounds => visibleBounds.Left < bounds.Right - 1
                            && visibleBounds.Right > bounds.Left + 1
                            && visibleBounds.Top < bounds.Bottom - 1
                            && visibleBounds.Bottom > bounds.Top + 1))
                            throw new InvalidOperationException("Store scrolling overlapped visible product cards.");
                        visibleCards.Add(visibleBounds);
                        if (!ReferenceEquals(card.DataContext, products[index]))
                        {
                            StartupDiagnostics.Stage($"store-scroll-wrong-product index={index}");
                            throw new InvalidOperationException("Store scrolling recycled a card with the wrong product.");
                        }
                        Windows.Foundation.Point position = card.TransformToVisual(StoreResultsHost)
                            .TransformPoint(new Windows.Foundation.Point());
                        if (positions.TryGetValue(index, out Windows.Foundation.Point previous)
                            && (Math.Abs(previous.X - position.X) > 1 || Math.Abs(previous.Y - position.Y) > 1))
                        {
                            StartupDiagnostics.Stage($"store-scroll-moved index={index} old-x={previous.X} old-y={previous.Y} new-x={position.X} new-y={position.Y}");
                            throw new InvalidOperationException("Store scrolling moved an existing product to a different row.");
                        }
                        positions[index] = position;
                        TextBlock name = FindStoreText(card, "StoreProductName")
                            ?? throw new InvalidOperationException("Store product name is missing.");
                        TextBlock price = FindStoreText(card, "StoreProductPrice")
                            ?? throw new InvalidOperationException("Store product price is missing.");
                        double nameBottom = name.TransformToVisual(card).TransformPoint(new Windows.Foundation.Point()).Y + name.ActualHeight;
                        double priceTop = price.TransformToVisual(card).TransformPoint(new Windows.Foundation.Point()).Y;
                        if (name.MaxLines != 2 || name.TextWrapping != TextWrapping.Wrap
                            || name.TextTrimming != TextTrimming.CharacterEllipsis
                            || nameBottom > priceTop + 1 || priceTop + price.ActualHeight > card.ActualHeight + 1)
                            throw new InvalidOperationException("Store name and price do not fit inside the card.");
                        if (ReferenceEquals(products[index], longNameProduct)
                            && (!name.IsTextTrimmed || name.ActualHeight < name.FontSize * 2))
                            throw new InvalidOperationException("A long store name did not occupy two lines with an ellipsis.");
                    }
                }
                if (positions.Count != products.Count)
                    throw new InvalidOperationException("Store scrolling did not reach every product.");
                StartupDiagnostics.Stage($"store-scroll-width-complete width={width} products={positions.Count} extent={extent}");
            }
            StartupDiagnostics.Stage("store-scroll-smoke-complete");
        }
        finally
        {
            StorePage.Width = originalWidth;
            StorePage.Height = originalHeight;
            longNameProduct.DisplayName = originalName;
            ViewModel.SelectedStoreKindIndex = originalKind;
            ViewModel.IsStoreLoading = wasLoading;
            StorePage.ChangeView(null, 0, null, disableAnimation: true);
        }
    }

    private static T? FindVisualChild<T>(DependencyObject root) where T : DependencyObject
    {
        for (int index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            DependencyObject child = VisualTreeHelper.GetChild(root, index);
            if (child is T match)
                return match;
            if (FindVisualChild<T>(child) is { } nested)
                return nested;
        }
        return null;
    }

    private static TextBlock? FindStoreText(DependencyObject root, string automationId)
    {
        for (int index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            DependencyObject child = VisualTreeHelper.GetChild(root, index);
            if (child is TextBlock text
                && Microsoft.UI.Xaml.Automation.AutomationProperties.GetAutomationId(text) == automationId)
                return text;
            if (FindStoreText(child, automationId) is { } match)
                return match;
        }
        return null;
    }

    private static async Task WaitForNextFrameAsync()
    {
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        void OnRendering(object? sender, object args) => completion.TrySetResult();
        CompositionTarget.Rendering += OnRendering;
        try
        {
            await completion.Task.WaitAsync(TimeSpan.FromSeconds(5));
        }
        finally
        {
            CompositionTarget.Rendering -= OnRendering;
        }
    }

    internal async Task VerifyStoreFilterToggleSmokeAsync()
    {
        string originalSearchText = ViewModel.StoreSearchText;
        int originalKindIndex = ViewModel.SelectedStoreKindIndex;
        int originalSortIndex = ViewModel.SelectedStoreSortIndex;
        bool originallyHidesOwned = ViewModel.HidesOwnedStoreProducts;
        try
        {
            ShowPage("store");
            if (StoreCharacterKindChip.IsChecked != true)
            {
                throw new InvalidOperationException(
                    "Store filter smoke: character was not the default product kind.");
            }

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
            StoreFilterToggle.UpdateLayout();
            filterPresenter = FindNamedDescendant<ContentPresenter>(
                StoreFilterToggle,
                "FilterTogglePresenter");
            if (StoreFilterPanel.Visibility != Visibility.Visible)
            {
                throw new InvalidOperationException("Store filter smoke: panel did not open.");
            }
            if (StoreFilterChevron.RenderTransform is not RotateTransform { Angle: 180 })
            {
                throw new InvalidOperationException("Store filter smoke: chevron did not rotate open.");
            }
            if (filterPresenter is null
                || IsTransparentBrush(filterPresenter.Background)
                || filterPresenter.BorderThickness.Left == 0)
            {
                throw new InvalidOperationException(
                    "Store filter smoke: open filter did not use a neutral surface.");
            }

            StorePage.UpdateLayout();
            double initialContentWidth = StorePageContent.ActualWidth;
            double initialContentOffset = StorePageContent
                .TransformToVisual(StorePage)
                .TransformPoint(new Windows.Foundation.Point())
                .X;

            await WaitForLoadedAsync(StoreSearchTextBox);
            if (!StoreSearchTextBox.Focus(FocusState.Programmatic))
            {
                throw new InvalidOperationException("Store filter smoke: search input did not receive focus.");
            }

            StoreSearchTextBox.Text = "x";
            QueueStoreSearchUpdate();
            StoreSearchTextBox.Text = "xz";
            QueueStoreSearchUpdate();
            StoreSearchTextBox.Text = "xz-no-sidey-product";
            QueueStoreSearchUpdate();
            await WaitForDispatcherTurnAsync();
            StorePage.UpdateLayout();
            double emptyContentOffset = StorePageContent
                .TransformToVisual(StorePage)
                .TransformPoint(new Windows.Foundation.Point())
                .X;
            if (!StringComparer.Ordinal.Equals(ViewModel.StoreSearchText, "xz-no-sidey-product")
                || ViewModel.HasVisibleStoreProducts
                || Math.Abs(StorePageContent.ActualWidth - initialContentWidth) > 0.5
                || Math.Abs(emptyContentOffset - initialContentOffset) > 0.5
                || StoreFilterPanel.Visibility != Visibility.Visible)
            {
                throw new InvalidOperationException(
                    "Store filter smoke: empty search results changed the content frame.");
            }

            ViewModel.SelectedStoreSortIndex = 2;
            ViewModel.HidesOwnedStoreProducts = true;
            StoreThrowableKindChip.IsChecked = true;
            OnResetStoreFiltersClick(StoreResetFiltersButton, new RoutedEventArgs());
            if (StoreSearchTextBox.Text.Length != 0
                || ViewModel.StoreSearchText.Length != 0
                || ViewModel.SelectedStoreKindIndex != (int)CommerceProductKind.Throwable
                || StoreThrowableKindChip.IsChecked != true
                || ViewModel.SelectedStoreSortIndex != 0
                || ViewModel.HidesOwnedStoreProducts)
            {
                throw new InvalidOperationException(
                    "Store filter smoke: reset did not restore filters while preserving product kind.");
            }
            StoreSearchTextBox.Text = "xz-no-sidey-product";
            QueueStoreSearchUpdate();
            await WaitForDispatcherTurnAsync();

            StoreFilterToggle.IsChecked = false;
            OnStoreFilterToggleClick(StoreFilterToggle, new RoutedEventArgs());
            await _storeFilterTransition;
            StoreFilterToggle.UpdateLayout();
            filterPresenter = FindNamedDescendant<ContentPresenter>(
                StoreFilterToggle,
                "FilterTogglePresenter");
            if (StoreFilterPanel.Visibility != Visibility.Collapsed
                || !StringComparer.Ordinal.Equals(StoreSearchTextBox.Text, "xz-no-sidey-product")
                || !StringComparer.Ordinal.Equals(ViewModel.StoreSearchText, "xz-no-sidey-product")
                || StoreFilterChevron.RenderTransform is not RotateTransform { Angle: 0 }
                || filterPresenter is null
                || !IsTransparentBrush(filterPresenter.Background)
                || filterPresenter.BorderThickness.Left != 0)
            {
                StartupDiagnostics.Stage(
                    $"store-filter-toggle-smoke-failed visibility={StoreFilterPanel.Visibility} query-retained={StringComparer.Ordinal.Equals(StoreSearchTextBox.Text, "xz-no-sidey-product")} query-applied={StringComparer.Ordinal.Equals(ViewModel.StoreSearchText, "xz-no-sidey-product")}");
                throw new InvalidOperationException(
                    "Store filter smoke: focused search did not close while preserving its query.");
            }

            StartupDiagnostics.Stage(
                "store-filter-toggle-smoke-complete focused-search=true query-preserved=true");
        }
        finally
        {
            ViewModel.StoreSearchText = originalSearchText;
            // A collapsed search field can still have a queued TextChanged callback.
            // Restore its input as well as the model before the next smoke test runs.
            StoreSearchTextBox.Text = originalSearchText;
            ViewModel.SelectedStoreSortIndex = originalSortIndex;
            ViewModel.HidesOwnedStoreProducts = originallyHidesOwned;
            RadioButton originalKindChip = originalKindIndex switch
            {
                (int)CommerceProductKind.Bubble => StoreBubbleKindChip,
                (int)CommerceProductKind.Throwable => StoreThrowableKindChip,
                _ => StoreCharacterKindChip,
            };
            originalKindChip.IsChecked = true;
            StoreFilterToggle.IsChecked = false;
            SetStoreFilterPanelExpanded(false);
            await WaitForDispatcherTurnAsync();
            if (!StringComparer.Ordinal.Equals(ViewModel.StoreSearchText, originalSearchText)
                || !StringComparer.Ordinal.Equals(StoreSearchTextBox.Text, originalSearchText))
            {
                throw new InvalidOperationException("Store filter smoke: search state was not restored.");
            }
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

            ContentDialog dialog = CreateStorePreviewDialog(product, previewStage, xamlRoot);
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

    internal static ContentDialog CreateStorePreviewDialog(
        StoreProductPreviewViewModel? product, StorePreviewStage previewStage, XamlRoot xamlRoot)
    {
        StackPanel content = product is null ? new StackPanel() : CreateStorePreviewContent(product, previewStage);
        if (product is null)
        {
            content.Children.Add(new Viewbox { Child = previewStage, Stretch = Stretch.Uniform, StretchDirection = StretchDirection.DownOnly });
        }
        var scroll = new ScrollViewer
        {
            Content = content,
            Width = 540,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            HorizontalScrollMode = ScrollMode.Disabled,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Padding = new Thickness(0, 0, 4, 0),
        };
        var dialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Content = scroll,
            RequestedTheme = (xamlRoot.Content as FrameworkElement)?.ActualTheme ?? ElementTheme.Default,
            CloseButtonText = I18n.Get("common.close"),
            DefaultButton = ContentDialogButton.Close,
        };
        // WinUI's default dialog content width is narrower than the preview stage.
        dialog.Resources["ContentDialogMaxWidth"] = 620d;
        void UpdateViewport(XamlRoot sender, XamlRootChangedEventArgs args)
        {
            scroll.MaxWidth = Math.Max(1, sender.Size.Width - 80);
            scroll.MaxHeight = Math.Max(1, sender.Size.Height - 160);
        }
        scroll.MaxWidth = Math.Max(1, xamlRoot.Size.Width - 80);
        scroll.MaxHeight = Math.Max(1, xamlRoot.Size.Height - 160);
        dialog.Opened += (_, _) => xamlRoot.Changed += UpdateViewport;
        dialog.Closed += (_, _) => xamlRoot.Changed -= UpdateViewport;
        return dialog;
    }

    internal static StackPanel CreateStorePreviewContent(StoreProductPreviewViewModel product, StorePreviewStage previewStage)
    {
        var content = new StackPanel { Spacing = 12 };
        content.Children.Add(new TextBlock
        {
            Text = product.DisplayName,
            FontSize = 22,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
        });
        content.Children.Add(new Viewbox
        {
            Child = previewStage,
            Stretch = Stretch.Uniform,
            StretchDirection = StretchDirection.DownOnly,
            HorizontalAlignment = HorizontalAlignment.Stretch,
        });
        var cards = new Grid { ColumnSpacing = 12, HorizontalAlignment = HorizontalAlignment.Stretch };
        cards.ColumnDefinitions.Add(new ColumnDefinition());
        cards.Children.Add(CreateStoreDetailCard(product, isKeepsake: product.IsKeepsake));
        if (product.RelatedKeepsake is { } keepsake)
        {
            cards.ColumnDefinitions.Add(new ColumnDefinition());
            Border keepsakeCard = CreateStoreDetailCard(keepsake, isKeepsake: true);
            Grid.SetColumn(keepsakeCard, 1);
            cards.Children.Add(keepsakeCard);
        }
        content.Children.Add(cards);
        return content;
    }

    internal static async Task VerifyStorePreviewLayoutAsync(ContentDialog dialog)
    {
        var scroll = (ScrollViewer)dialog.Content;
        if (!scroll.IsLoaded)
        {
            var loaded = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            void OnLoaded(object sender, RoutedEventArgs args) => loaded.TrySetResult();
            scroll.Loaded += OnLoaded;
            try
            {
                await loaded.Task.WaitAsync(TimeSpan.FromSeconds(10));
            }
            finally
            {
                scroll.Loaded -= OnLoaded;
            }
        }
        scroll.UpdateLayout();
        var content = (StackPanel)scroll.Content;
        if (scroll.ViewportWidth <= 0 || content.ActualWidth > scroll.ViewportWidth + 1)
        {
            throw new InvalidOperationException("Store detail content exceeds its viewport width.");
        }
        async Task VerifyChildrenAsync(DependencyObject parent)
        {
            for (int index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++)
            {
                DependencyObject child = VisualTreeHelper.GetChild(parent, index);
                if (child is Viewbox { Child: StorePreviewStage stage })
                {
                    Windows.Foundation.Rect bounds = stage.TransformToVisual(content).TransformBounds(
                        new Windows.Foundation.Rect(0, 0, stage.ActualWidth, stage.ActualHeight));
                    if (bounds.Left < -1 || bounds.Right > content.ActualWidth + 1)
                    {
                        throw new InvalidOperationException("Store preview stage is clipped horizontally.");
                    }
                }
                if (child is StoreProductArtwork artwork)
                {
                    Windows.Foundation.Point position = artwork.TransformToVisual(content).TransformPoint(new Windows.Foundation.Point());
                    if (position.X < -1 || position.X + artwork.ActualWidth > content.ActualWidth + 1)
                    {
                        throw new InvalidOperationException("Store detail artwork is clipped horizontally.");
                    }
                    scroll.ChangeView(null, position.Y, null, disableAnimation: true);
                    scroll.UpdateLayout();
                    await artwork.VerifyRenderedArtworkAsync();
                }
                else
                {
                    await VerifyChildrenAsync(child);
                }
            }
        }
        await VerifyChildrenAsync(content);
        scroll.ChangeView(null, 0, null, disableAnimation: true);
        StartupDiagnostics.Stage("store-detail-layout-smoke-complete");
    }

    internal static async Task VerifyStorePurchaseButtonAsync(XamlRoot xamlRoot)
    {
        CommerceProduct catalogProduct = WindowsCommerceCatalog.Products[0];
        int calls = 0;
        var invoked = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var product = new StoreProductPreviewViewModel(catalogProduct, "Purchase smoke", "", "",
            () => { calls++; invoked.TrySetResult(); return Task.CompletedTask; }, () => { });
        var state = new CommerceProductState(catalogProduct, GoogleConnected: true, CommercePurchaseState.Available);
        product.Apply(state, commerceEnabled: true, isOwned: false);
        Border card = CreateStoreDetailCard(product, isKeepsake: false);
        var dialog = new ContentDialog { XamlRoot = xamlRoot, Content = card, CloseButtonText = "Close" };
        var opened = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        dialog.Opened += (_, _) => opened.TrySetResult();
        Windows.Foundation.IAsyncOperation<ContentDialogResult> showing = dialog.ShowAsync();
        try
        {
            await opened.Task.WaitAsync(TimeSpan.FromSeconds(10));
            var footer = (StackPanel)((Grid)card.Child).Children.Last();
            if (footer.Children.Last() is not Button button
                || !ReferenceEquals(button.Command, product.ActionCommand)
                || !button.IsEnabled || !Equals(button.Content, product.DetailStatusText))
                throw new InvalidOperationException("Store purchase button is not connected.");
            var peer = new Microsoft.UI.Xaml.Automation.Peers.ButtonAutomationPeer(button);
            var invoke = (Microsoft.UI.Xaml.Automation.Provider.IInvokeProvider)peer.GetPattern(
                Microsoft.UI.Xaml.Automation.Peers.PatternInterface.Invoke);
            invoke.Invoke();
            await invoked.Task.WaitAsync(TimeSpan.FromSeconds(10));
            if (calls != 1)
                throw new InvalidOperationException("Store purchase button did not invoke exactly once.");
            product.Apply(state with { IsWorking = true }, commerceEnabled: true, isOwned: false);
            if (button.IsEnabled)
                throw new InvalidOperationException("Working store product remains purchasable.");
            product.Apply(state, commerceEnabled: true, isOwned: true);
            if (button.IsEnabled || !Equals(button.Content, product.DetailStatusText))
                throw new InvalidOperationException("Owned store product remains purchasable.");
            product.Apply(state, commerceEnabled: false, isOwned: false);
            if (button.IsEnabled)
                throw new InvalidOperationException("Preview-only store product remains purchasable.");
            StartupDiagnostics.Stage("store-purchase-button-smoke-complete");
        }
        finally
        {
            dialog.Hide();
            await showing;
        }
    }

    private static Border CreateStoreDetailCard(StoreProductPreviewViewModel product, bool isKeepsake)
    {
        var content = new Grid { RowSpacing = 12 };
        foreach (GridLength height in new[] { GridLength.Auto, new GridLength(88), GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto })
        {
            content.RowDefinitions.Add(new RowDefinition { Height = height });
        }
        var header = new TextBlock
        {
            Text = I18n.Get(isKeepsake ? "store.keepsake" : product.Kind switch
            {
                CommerceProductKind.Character => "profile.character",
                CommerceProductKind.Bubble => "profile.bubble",
                _ => "profile.throwable",
            }),
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            FontSize = 12,
        };
        content.Children.Add(header);
        var artwork = new StoreProductArtwork
        {
            ProductKind = product.Kind,
            CatalogItemId = product.CatalogItemId,
            CharacterId = product.CharacterId,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Stretch,
        };
        var artworkSurface = new Border
        {
            Style = (Style)Application.Current.Resources["SideyStoreArtworkSurfaceStyle"],
            Child = artwork,
        };
        Grid.SetRow(artworkSurface, 1);
        content.Children.Add(artworkSurface);
        foreach ((string property, int row) in new[] { (nameof(product.DisplayName), 2), (nameof(product.Description), 3) })
        {
            var text = new TextBlock
            {
                TextWrapping = TextWrapping.Wrap,
                TextAlignment = TextAlignment.Center,
                FontSize = property == nameof(product.DisplayName) ? 14 : 12,
                FontWeight = property == nameof(product.DisplayName)
                    ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal,
            };
            text.SetBinding(TextBlock.TextProperty, new Microsoft.UI.Xaml.Data.Binding
            {
                Source = product,
                Path = new PropertyPath(property),
                Mode = Microsoft.UI.Xaml.Data.BindingMode.OneWay,
            });
            Grid.SetRow(text, row);
            content.Children.Add(text);
        }
        var footer = new StackPanel { Spacing = 6 };
        var price = new TextBlock { TextAlignment = TextAlignment.Center };
        price.SetBinding(TextBlock.TextProperty, new Microsoft.UI.Xaml.Data.Binding
        {
            Source = product,
            Path = new PropertyPath(nameof(product.FormattedPrice)),
            Mode = Microsoft.UI.Xaml.Data.BindingMode.OneWay,
        });
        footer.Children.Add(price);
        if (isKeepsake)
        {
            footer.Children.Add(new TextBlock
            {
                Text = I18n.Get("store.soldSeparately"),
                TextWrapping = TextWrapping.Wrap,
                TextAlignment = TextAlignment.Center,
                FontSize = 12,
                Style = (Style)Application.Current.Resources["SideyStoreSecondaryTextStyle"],
            });
        }
        var purchase = new Button
        {
            Command = product.ActionCommand,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            Style = (Style)Application.Current.Resources["AccentButtonStyle"],
        };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(purchase, "StorePurchase_" + product.ProductId);
        purchase.SetBinding(ContentControl.ContentProperty, new Microsoft.UI.Xaml.Data.Binding
        {
            Source = product,
            Path = new PropertyPath(nameof(product.DetailStatusText)),
            Mode = Microsoft.UI.Xaml.Data.BindingMode.OneWay,
        });
        purchase.SetBinding(Control.IsEnabledProperty, new Microsoft.UI.Xaml.Data.Binding
        {
            Source = product,
            Path = new PropertyPath(nameof(product.IsActionEnabled)),
            Mode = Microsoft.UI.Xaml.Data.BindingMode.OneWay,
        });
        footer.Children.Add(purchase);
        Grid.SetRow(footer, 4);
        content.Children.Add(footer);
        return new Border
        {
            Style = (Style)Application.Current.Resources["SideySettingsCardStyle"],
            Padding = new Thickness(16),
            Child = content,
        };
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
            if (tag != "profile")
            {
                AnimatePageRefresh(selectedPage);
            }
        }
    }

    private void OnStoreKindChipChecked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not RadioButton { Tag: string tag }
            || !int.TryParse(tag, out int selectedIndex)
            || MainRoot.DataContext is not MainWindowViewModel viewModel)
        {
            return;
        }

        int previousIndex = viewModel.SelectedStoreKindIndex;
        ApplyStoreKindChipStyles(selectedIndex);
        if (selectedIndex < 0 || selectedIndex == previousIndex)
        {
            return;
        }

        viewModel.SelectedStoreKindIndex = selectedIndex;
        AnimateSiblingPage(
            StoreResultsHost,
            selectedIndex > previousIndex ? 24d : -24d);
    }

    private void ApplyStoreKindChipStyles(int selectedIndex)
    {
        if (StoreCharacterKindChip is null
            || StoreBubbleKindChip is null
            || StoreThrowableKindChip is null)
        {
            return;
        }

        var defaultStyle = (Style)Application.Current.Resources["SideyStoreKindChipStyle"];
        var selectedStyle = (Style)Application.Current.Resources["SideyStoreKindChipSelectedStyle"];
        RadioButton[] chips =
        [
            StoreCharacterKindChip,
            StoreBubbleKindChip,
            StoreThrowableKindChip,
        ];
        for (int index = 0; index < chips.Length; index++)
        {
            chips[index].Style = index == selectedIndex ? selectedStyle : defaultStyle;
        }
    }

    private static void AnimatePageRefresh(FrameworkElement element) =>
        AnimateElement(element, horizontalOffset: 0, verticalOffset: 16, durationMilliseconds: 250);

    private static void AnimateSiblingPage(FrameworkElement element, double horizontalOffset) =>
        AnimateElement(element, horizontalOffset, verticalOffset: 0, durationMilliseconds: 167);

    private async void OnRoomHeaderClick(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not Button header
            || header.DataContext is not RoomCardViewModel room
            || header.Tag is not FrameworkElement body
            || !_roomExpansionAnimations.Add(room.Room.Id))
        {
            return;
        }

        var headerLayout = VisualTreeHelper.GetParent(header) as Grid;
        FontIcon? chevron = headerLayout is null
            ? null
            : FindNamedDescendant<FontIcon>(headerLayout, "RoomExpansionChevron");
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
            Duration = TimeSpan.FromMilliseconds(167),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
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

        var duration = new Duration(TimeSpan.FromMilliseconds(167));
        var easing = new CubicEase { EasingMode = EasingMode.EaseOut };
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
            bool isExpanded = StoreFilterPanel.Visibility == Visibility.Visible;
            StoreFilterToggle.IsChecked = isExpanded;
            ApplyStoreFilterToggleSurface(isExpanded);
            return;
        }

        bool requestedExpanded = StoreFilterToggle.IsChecked == true;
        ApplyStoreFilterToggleSurface(requestedExpanded);
        _storeFilterTransition = TransitionStoreFilterPanelAsync(requestedExpanded);
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

        var duration = new Duration(TimeSpan.FromMilliseconds(167));
        var easing = new CubicEase { EasingMode = EasingMode.EaseOut };
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
        StoreFilterToggle.IsChecked = isExpanded;
        ApplyStoreFilterToggleSurface(isExpanded);
        StoreFilterPanel.Visibility = isExpanded ? Visibility.Visible : Visibility.Collapsed;
        StoreFilterPanel.Height = double.NaN;
        StoreFilterPanel.Opacity = 1;
        if (StoreFilterPanel.RenderTransform is TranslateTransform transform)
        {
            transform.Y = 0;
        }
        SetChevronAngle(StoreFilterChevron, isExpanded ? 180 : 0);
    }

    private void ApplyStoreFilterToggleSurface(bool isExpanded)
    {
        string styleKey = isExpanded
            ? "SideyStoreFilterToggleExpandedStyle"
            : "SideyStoreFilterToggleStyle";
        StoreFilterToggle.Style = (Style)Application.Current.Resources[styleKey];
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
        SideyWindowTheme.ApplyBackdrop(this, MainFallbackBackground);
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
        MainRoot.Loaded -= OnResponsiveRootLoaded;
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
