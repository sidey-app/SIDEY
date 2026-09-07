namespace Sidey.Platform.Windows.Tests;

public sealed class MacParityUiSourceTests
{
    [Fact]
    public void FirstRunUsesAWinUiLandingAndStepByStepOnboardingWindow()
    {
        var app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");
        var xaml = ReadRepositoryFile("windows", "src", "Sidey.App", "OnboardingWindow.xaml");
        var window = ReadRepositoryFile(
            "windows", "src", "Sidey.App", "OnboardingWindow.xaml.cs");
        var coordinator = ReadRepositoryFile("windows", "src", "Sidey.App", "AppCoordinator.cs");
        var korean = ReadRepositoryFile("windows", "src", "Sidey.App", "Langs", "ko-KR.json");

        Assert.Contains("Preferences.OnboardingCompleted", app, StringComparison.Ordinal);
        Assert.Contains("new OnboardingWindow", app, StringComparison.Ordinal);
        Assert.Contains("onboarding-window-activated", app, StringComparison.Ordinal);
        Assert.Contains("Key=onboarding.tagline", xaml, StringComparison.Ordinal);
        Assert.Contains("Key=onboarding.stepProfile", xaml, StringComparison.Ordinal);
        Assert.Contains("Key=onboarding.stepGroup", xaml, StringComparison.Ordinal);
        Assert.Contains("Key=onboarding.completeTitle", xaml, StringComparison.Ordinal);
        Assert.Contains("친구들이 화면 곁에 함께합니다.", korean, StringComparison.Ordinal);
        Assert.Contains("SIDEY를 시작할 준비가 됐어요", korean, StringComparison.Ordinal);
        Assert.Contains("MicaBackdrop", window, StringComparison.Ordinal);
        Assert.Contains("MicaKind.Base", window, StringComparison.Ordinal);
        Assert.DoesNotContain("MicaKind.BaseAlt", window, StringComparison.Ordinal);
        Assert.Contains("PrepareForClose", window, StringComparison.Ordinal);
        Assert.Contains("OnboardingRoot.DataContext = null", window, StringComparison.Ordinal);
        Assert.Contains("ViewModel.Dispose()", window, StringComparison.Ordinal);
        Assert.Contains("CompleteOnboardingAsync", coordinator, StringComparison.Ordinal);
        Assert.Contains("OnboardingCompleted = true", coordinator, StringComparison.Ordinal);
        Assert.DoesNotContain("|| (profile is not null && snapshot.Rooms.Count > 0)", coordinator, StringComparison.Ordinal);
        Assert.Contains("Command=\"{Binding SkipGroupCommand}\"", xaml, StringComparison.Ordinal);
    }

    [Fact]
    public void CompletedLaunchStaysInTrayAndSettingsCloseHidesTheWindow()
    {
        var app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");
        var mainWindow = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml.cs");

        Assert.Contains("if (!coordinator.State.Preferences.OnboardingCompleted)", app, StringComparison.Ordinal);
        Assert.Contains("EnsureMainWindow();", app, StringComparison.Ordinal);
        Assert.Contains("_window = _mainWindow;", app, StringComparison.Ordinal);
        Assert.Contains("completed-launch-window-hidden", app, StringComparison.Ordinal);
        Assert.DoesNotContain("StartupDiagnostics.Stage(\"main-window-activated\")", app, StringComparison.Ordinal);
        Assert.Contains("MainWindow mainWindow = EnsureMainWindow();", app, StringComparison.Ordinal);
        Assert.Contains("mainWindow.Activate();", app, StringComparison.Ordinal);
        Assert.Contains("if (_allowClose || !_trayAvailable)", mainWindow, StringComparison.Ordinal);
        Assert.Contains("args.Cancel = true", mainWindow, StringComparison.Ordinal);
        Assert.Contains("AppWindow.Hide()", mainWindow, StringComparison.Ordinal);
        Assert.Contains("_allowClose = true", mainWindow, StringComparison.Ordinal);
        Assert.Contains("MainRoot.DataContext = null", mainWindow, StringComparison.Ordinal);
        Assert.Contains("_lifetime.Cancel()", mainWindow, StringComparison.Ordinal);
    }

    [Fact]
    public void OnboardingHasNoPreviewOnlyEntryPointOrState()
    {
        var app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");
        var xaml = ReadRepositoryFile("windows", "src", "Sidey.App", "OnboardingWindow.xaml");
        var viewModel = ReadRepositoryFile(
            "windows", "src", "Sidey.Presentation", "ViewModels", "OnboardingViewModel.cs");
        var guard = ReadRepositoryFile(
            "windows", "src", "Sidey.App", "SingleInstanceGuard.cs");
        var readme = ReadRepositoryFile("windows", "README.md");
        var organizer = ReadRepositoryFile("scripts", "windows", "organize-publish.ps1");
        var packager = ReadRepositoryFile("scripts", "windows", "package.ps1");

        Assert.DoesNotContain("--onboarding-preview", app, StringComparison.Ordinal);
        Assert.DoesNotContain("RequestOnboardingPreview", app, StringComparison.Ordinal);
        Assert.DoesNotContain("OnboardingPreview", guard, StringComparison.Ordinal);
        Assert.DoesNotContain("onboarding-preview", guard, StringComparison.Ordinal);
        Assert.DoesNotContain("IsPreviewMode", viewModel, StringComparison.Ordinal);
        Assert.DoesNotContain("onboarding.previewNotice", xaml, StringComparison.Ordinal);
        Assert.DoesNotContain("--onboarding-preview", readme, StringComparison.Ordinal);
        Assert.DoesNotContain("SIDEY-Onboarding-Preview.cmd", organizer, StringComparison.Ordinal);
        Assert.DoesNotContain("SIDEY-Onboarding-Preview.cmd", packager, StringComparison.Ordinal);
    }

    [Fact]
    public void SettingsNavigationMatchesMacAndDoesNotContainHistory()
    {
        var source = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml");

        Assert.Contains("Key=navigation.profile", source, StringComparison.Ordinal);
        Assert.Contains("Key=navigation.groups", source, StringComparison.Ordinal);
        Assert.Contains("Key=navigation.store", source, StringComparison.Ordinal);
        Assert.Contains("Key=navigation.settings", source, StringComparison.Ordinal);
        Assert.DoesNotContain("HistoryPage", source, StringComparison.Ordinal);
    }

    [Fact]
    public void TrayAndHistoryPreserveMacInteractionContract()
    {
        var tray = ReadRepositoryFile("windows", "src", "Sidey.Platform.Windows", "TrayIconService.cs");
        var appXaml = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml");
        var historyXaml = ReadRepositoryFile("windows", "src", "Sidey.App", "HistoryWindow.xaml");
        var historyViewModel = ReadRepositoryFile(
            "windows", "src", "Sidey.Presentation", "ViewModels", "HistoryWindowViewModel.cs");
        var gateway = ReadRepositoryFile("windows", "src", "Sidey.Infrastructure", "SupabaseBackendGateway.cs");

        Assert.Contains("tray.activeGroup", tray, StringComparison.Ordinal);
        Assert.Contains("tray.history", tray, StringComparison.Ordinal);
        Assert.Contains("tray.store", tray, StringComparison.Ordinal);
        Assert.Contains("tray.exit", tray, StringComparison.Ordinal);
        Assert.DoesNotContain("Append(menu, TrayCommand.Open", tray, StringComparison.Ordinal);
        Assert.DoesNotContain("SetMenuDefaultItem", tray, StringComparison.Ordinal);
        Assert.DoesNotContain("ApplyMenuIcon", tray, StringComparison.Ordinal);
        Assert.DoesNotContain("TrayMenuIconSet", tray, StringComparison.Ordinal);
        Assert.Contains("NativeMenuFlags", tray, StringComparison.Ordinal);
        Assert.Contains("OverlayHiddenCheckState", tray, StringComparison.Ordinal);
        Assert.Contains("Text=\"{Binding EmptyMessage}\"", historyXaml, StringComparison.Ordinal);
        Assert.Contains("Text=\"{Binding EmptyDescription}\"", historyXaml, StringComparison.Ordinal);
        Assert.Contains("SideyAccentBackground10Brush", historyXaml, StringComparison.Ordinal);
        Assert.Contains("SideyAccentBackground12Brush", historyXaml, StringComparison.Ordinal);
        Assert.Contains("SideyAccentForegroundBrush", historyXaml, StringComparison.Ordinal);
        Assert.DoesNotContain("AccentFillColorSecondaryBrush", historyXaml, StringComparison.Ordinal);
        Assert.Contains("Opacity=\"0.10\"", appXaml, StringComparison.Ordinal);
        Assert.Contains("Opacity=\"0.12\"", appXaml, StringComparison.Ordinal);
        Assert.Contains("history.empty", historyViewModel, StringComparison.Ordinal);
        Assert.Contains("history.emptyDescription", historyViewModel, StringComparison.Ordinal);
        Assert.DoesNotContain("새로 고침", historyXaml, StringComparison.Ordinal);
        Assert.Contains("ToLocalTime()", historyViewModel, StringComparison.Ordinal);
        Assert.Contains("ToString(\"g\"", historyViewModel, StringComparison.Ordinal);
        Assert.Contains("order=created_at.desc,id.desc", gateway, StringComparison.Ordinal);
        Assert.Contains("created_at.lt.", gateway, StringComparison.Ordinal);
        Assert.Contains("id.lt.", gateway, StringComparison.Ordinal);
        Assert.Contains("boundedLimit + 1", gateway, StringComparison.Ordinal);
        Assert.Contains("commerce_entitlements?status=eq.active", gateway, StringComparison.Ordinal);
        Assert.Contains("LoadActiveEntitlementKeysIfAvailableAsync", gateway, StringComparison.Ordinal);
        Assert.Contains("MessageLedger.ConfirmedRetention", gateway, StringComparison.Ordinal);
        Assert.Contains(
            "(!isActiveRoom || _state.Preferences.QuietMode)",
            ReadRepositoryFile("windows", "src", "Sidey.App", "AppCoordinator.cs"),
            StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsNotifiesOnceWhenTheServerConnectionFails()
    {
        var app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");
        var tray = ReadRepositoryFile("windows", "src", "Sidey.Platform.Windows", "TrayIconService.cs");

        Assert.Contains("UpdateConnectionFailureNotification", app, StringComparison.Ordinal);
        Assert.Contains("ConnectionFailureNotificationDelay = TimeSpan.FromSeconds(15)", app, StringComparison.Ordinal);
        Assert.Contains("ScheduleConnectionFailureNotification", app, StringComparison.Ordinal);
        Assert.Contains("CancelConnectionFailureNotification", app, StringComparison.Ordinal);
        Assert.DoesNotContain("_hasEstablishedServerConnection", app, StringComparison.Ordinal);
        Assert.Contains("ConnectionFailureNotificationCooldown", app, StringComparison.Ordinal);
        Assert.Contains("NotifyConnectionFailure", tray, StringComparison.Ordinal);
        Assert.Contains("NotifyIconInfo", tray, StringComparison.Ordinal);
        Assert.DoesNotContain("ToastNotification", app, StringComparison.Ordinal);
        Assert.DoesNotContain("AppNotification", app, StringComparison.Ordinal);
    }

    [Fact]
    public void RealtimeSyncPrecedesOverlayAndPresenceColorsMatchMacV103()
    {
        var coordinator = ReadRepositoryFile("windows", "src", "Sidey.App", "AppCoordinator.cs");
        var visuals = ReadRepositoryFile("windows", "src", "Sidey.Overlay", "PixelTextVisualCache.cs");
        var renderer = ReadRepositoryFile("windows", "src", "Sidey.Overlay", "LayeredPixelWorldRenderer.cs");

        Assert.Contains("&& _state.ActiveRoomConnected", coordinator, StringComparison.Ordinal);
        Assert.Contains("private void SetRealtimeConnection(RealtimeConnectionStatus status)", coordinator, StringComparison.Ordinal);
        Assert.Contains("RecoveryReconciled", coordinator, StringComparison.Ordinal);
        Assert.Contains("PresenceState.Offline => Color.FromArgb(255, 255, 59, 48)", visuals, StringComparison.Ordinal);
        Assert.Contains("PresenceState.Reconnecting => Color.FromArgb(255, 142, 142, 147)", visuals, StringComparison.Ordinal);
        Assert.Contains("desaturate: node.Member.Presence == PresenceState.Offline", renderer, StringComparison.Ordinal);
    }

    [Fact]
    public void ThrowActionsKeepFacingAndImpactAtTheMacTorsoPosition()
    {
        var renderer = ReadRepositoryFile(
            "windows", "src", "Sidey.Overlay", "LayeredPixelWorldRenderer.cs");

        Assert.Contains("if (actionFrame is null", renderer, StringComparison.Ordinal);
        Assert.Contains("ShouldMirrorForVelocity(node.Agent.Velocity)", renderer, StringComparison.Ordinal);
        Assert.Contains("ShouldMirrorEmitter(cannon)", renderer, StringComparison.Ordinal);
        Assert.Contains("projectile.Start = FootPoint(actor.Agent.TrackPosition)", renderer, StringComparison.Ordinal);
        Assert.Contains("var endpoint = FootPoint(target.Agent.TrackPosition)", renderer, StringComparison.Ordinal);
        Assert.Contains("point = ImpactPoint(end)", renderer, StringComparison.Ordinal);
        Assert.Contains("double inward = 10d * _dpiScale", renderer, StringComparison.Ordinal);
    }

    [Fact]
    public void DevelopmentUpdaterWatchesAtTheStructuredDeploymentRoot()
    {
        var source = ReadRepositoryFile("windows", "src", "Sidey.App", "DevelopmentUpdateService.cs");
        var project = ReadRepositoryFile("windows", "src", "Sidey.App", "Sidey.App.csproj");
        var app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");

        Assert.Contains("SideyDeploymentPaths.DeploymentRoot()", source, StringComparison.Ordinal);
        Assert.Contains("<Compile Remove=\"DevelopmentUpdateService.cs\" />", project, StringComparison.Ordinal);
        Assert.Contains("Condition=\"'$(Configuration)' != 'Debug'\"", project, StringComparison.Ordinal);
        Assert.Contains("#if DEBUG", app, StringComparison.Ordinal);
    }

    [Fact]
    public void ComposerMatchesMacFocusDismissAndPlaceholderContract()
    {
        var xaml = ReadRepositoryFile("windows", "src", "Sidey.App", "ComposerWindow.xaml");
        var source = ReadRepositoryFile("windows", "src", "Sidey.App", "ComposerWindow.xaml.cs");
        var viewModel = ReadRepositoryFile(
            "windows", "src", "Sidey.Presentation", "ViewModels", "ComposerViewModel.cs");

        Assert.Contains("PlaceholderText=\"{i18n:I18n Key=composer.placeholder}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Padding=\"10,6,10,0\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Width=\"400\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Height=\"56\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Command=\"{Binding CloseCommand}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Command=\"{Binding SendCommand}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("<SymbolIcon Symbol=\"Send\" />", xaml, StringComparison.Ordinal);
        Assert.DoesNotContain("&#xE74D;", xaml, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("FocusAttemptCount = 3", source, StringComparison.Ordinal);
        Assert.Contains("DispatcherQueue _uiDispatcherQueue", source, StringComparison.Ordinal);
        Assert.Contains("DispatcherQueue.GetForCurrentThread()", source, StringComparison.Ordinal);
        Assert.Contains("_uiDispatcherQueue.TryEnqueue(() =>", source, StringComparison.Ordinal);
        Assert.Contains("if (!_isClosed)", source, StringComparison.Ordinal);
        Assert.DoesNotContain(
            "OnCloseRequested() => DispatcherQueue.TryEnqueue",
            source,
            StringComparison.Ordinal);
        Assert.Contains("if (_isClosed || !_isVisible || _isHiding)", source, StringComparison.Ordinal);
        Assert.Contains("_isHiding = true", source, StringComparison.Ordinal);
        Assert.Contains("_isVisible = false", source, StringComparison.Ordinal);
        Assert.DoesNotContain("AppWindow.IsVisible", source, StringComparison.Ordinal);
        Assert.Contains("MessageInput.Focus(FocusState.Programmatic)", source, StringComparison.Ordinal);
        Assert.Equal(2, CountOccurrences(source, "SideyWindowActivation.BringToForeground(this);"));
        Assert.Contains("WindowActivationState.Deactivated", source, StringComparison.Ordinal);
        Assert.Contains("HideComposer();", source, StringComparison.Ordinal);
        Assert.Contains("ViewModel.OnHidden();", source, StringComparison.Ordinal);
        Assert.Contains("AppWindow.ResizeClient", source, StringComparison.Ordinal);
        Assert.Contains("AppWindow.Closing += OnAppWindowClosing", source, StringComparison.Ordinal);
        Assert.Contains("args.Cancel = true", source, StringComparison.Ordinal);
        Assert.Contains("CloseForExit()", source, StringComparison.Ordinal);
        Assert.Contains("CancelAutoClose();", viewModel, StringComparison.Ordinal);
        Assert.Contains("TimeSpan.FromSeconds(5)", viewModel, StringComparison.Ordinal);
    }

    [Fact]
    public void ComposerDoesNotMutateBorderOrTitleBarAtRuntime()
    {
        var source = ReadRepositoryFile("windows", "src", "Sidey.App", "ComposerWindow.xaml.cs");

        Assert.DoesNotContain("SetBorderAndTitleBar", source, StringComparison.Ordinal);
        Assert.DoesNotContain("AppWindow.SetPresenter", source, StringComparison.Ordinal);
        Assert.DoesNotContain("ExtendsContentIntoTitleBar", source, StringComparison.Ordinal);
    }

    [Fact]
    public void CharacterPreviewsDoNotKeepXamlCanvasResourcesAlive()
    {
        var xaml = ReadRepositoryFile(
            "windows", "src", "Sidey.App", "Controls", "PixelCharacterPreview.xaml");
        var source = ReadRepositoryFile(
            "windows", "src", "Sidey.App", "Controls", "PixelCharacterPreview.xaml.cs");
        var project = ReadRepositoryFile("windows", "src", "Sidey.App", "Sidey.App.csproj");

        Assert.Contains("<Image", xaml, StringComparison.Ordinal);
        Assert.Contains("x:Name=\"PreviewImage\"", xaml, StringComparison.Ordinal);
        Assert.DoesNotContain("CanvasControl", xaml, StringComparison.Ordinal);
        Assert.DoesNotContain("CanvasControl", source, StringComparison.Ordinal);
        Assert.Contains("StorePreviewImageLoader.LoadFrameAsync", source, StringComparison.Ordinal);
        Assert.Contains("CancelPendingLoad()", source, StringComparison.Ordinal);
        Assert.Contains("cancellation.Token", source, StringComparison.Ordinal);
        Assert.Contains("|| !IsLoaded", source, StringComparison.Ordinal);
        Assert.DoesNotContain(
            "<PackageReference Include=\"Microsoft.Graphics.Win2D\" />",
            project,
            StringComparison.Ordinal);
    }

    [Fact]
    public void MessageBubblesMatchMacStackTailTypographyAndInsets()
    {
        var source = ReadRepositoryFile(
            "windows", "src", "Sidey.Overlay", "PixelTextVisualCache.cs");
        var renderer = ReadRepositoryFile(
            "windows", "src", "Sidey.Overlay", "LayeredPixelWorldRenderer.cs");
        var ledger = ReadRepositoryFile(
            "windows", "src", "Sidey.Core", "Domain", "MessageLedger.cs");

        Assert.Contains("BubbleMaximumWidthDip = 220f", source, StringComparison.Ordinal);
        Assert.Contains("BubbleMinimumWidthDip = 28f", source, StringComparison.Ordinal);
        Assert.Contains("BubbleHorizontalPaddingDip = 8f", source, StringComparison.Ordinal);
        Assert.Contains("BubbleVerticalPaddingDip = 7f", source, StringComparison.Ordinal);
        Assert.Contains("NameplateFontSizeDip = 11f", source, StringComparison.Ordinal);
        Assert.Contains("BubbleFontSizeDip = NameplateFontSizeDip", source, StringComparison.Ordinal);
        Assert.Contains("var (width, height) = MeasureBubble(bubble.Body)", source, StringComparison.Ordinal);
        Assert.Contains("naturalLayout.LayoutBoundsIncludingTrailingWhitespace", source, StringComparison.Ordinal);
        Assert.Contains("wrappedLayout.LayoutBoundsIncludingTrailingWhitespace", source, StringComparison.Ordinal);
        Assert.DoesNotContain("var bounds = layout.DrawBounds", source, StringComparison.Ordinal);
        Assert.DoesNotContain("66f", source, StringComparison.Ordinal);
        Assert.Contains("MaximumVisiblePerSender = 2", ledger, StringComparison.Ordinal);
        Assert.Contains("IReadOnlyDictionary<Guid, PremultipliedVisual> MessageBubbles", source, StringComparison.Ordinal);
        Assert.Contains("BuildTypingFrame(\".\", key.TypingBubbleStyleId)", source, StringComparison.Ordinal);
        Assert.Contains("BuildTypingFrame(\"..\", key.TypingBubbleStyleId)", source, StringComparison.Ordinal);
        Assert.Contains("BuildTypingFrame(\"...\", key.TypingBubbleStyleId)", source, StringComparison.Ordinal);
        Assert.Contains("ResolveTheme(bubble.BubbleStyleId)", source, StringComparison.Ordinal);
        Assert.Contains("dpi / 96d", source, StringComparison.Ordinal);
        Assert.Contains("PixelVisualBodyBounds", source, StringComparison.Ordinal);
        Assert.Contains("leadingOverflow", source, StringComparison.Ordinal);
        Assert.DoesNotContain("bubble.Body.Length * 8d", renderer, StringComparison.Ordinal);
    }

    [Fact]
    public void AppSettingsExposeMacTitlesAndDescriptions()
    {
        var xaml = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml");
        var source = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml.cs");
        var minimumSize = ReadRepositoryFile(
            "windows", "src", "Sidey.Platform.Windows", "WindowsMinimumSizeController.cs");

        Assert.DoesNotContain("PaneTitle=", xaml, StringComparison.Ordinal);
        Assert.Contains("Key=settings.overlayDescription", xaml, StringComparison.Ordinal);
        Assert.Contains("Key=settings.quietModeDescription", xaml, StringComparison.Ordinal);
        Assert.Contains("Key=settings.rightClickThrowDescription", xaml, StringComparison.Ordinal);
        Assert.Contains("Key=settings.offlineMembersDescription", xaml, StringComparison.Ordinal);
        Assert.Contains("Key=settings.monitorDescription", xaml, StringComparison.Ordinal);
        Assert.Contains("NavigationViewContentBackground\" Color=\"Transparent", xaml, StringComparison.Ordinal);
        Assert.Contains("HorizontalAlignment=\"Right\"", xaml, StringComparison.Ordinal);
        Assert.Contains("OffContent=\"\" OnContent=\"\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Width=\"48\" MinWidth=\"0\"", xaml, StringComparison.Ordinal);
        Assert.Contains("PaneDisplayMode=\"Auto\"", xaml, StringComparison.Ordinal);
        Assert.Contains("CompactModeThresholdWidth=\"0\"", xaml, StringComparison.Ordinal);
        Assert.Contains("CompactPaneLength=\"48\"", xaml, StringComparison.Ordinal);
        Assert.Contains("ExpandedModeThresholdWidth=\"960\"", xaml, StringComparison.Ordinal);
        Assert.Equal(1, CountOccurrences(xaml, "x:Name=\"CompactConnectionDot\""));
        Assert.Contains("x:Name=\"CompactConnectionStatus\"", xaml, StringComparison.Ordinal);
        Assert.Contains("x:Name=\"ConnectionStatusRoot\" Width=\"210\"", xaml, StringComparison.Ordinal);
        Assert.Contains("ConnectionStatusRoot.Width = RootNavigation.CompactPaneLength", source, StringComparison.Ordinal);
        Assert.Contains("PaneClosing=\"OnNavigationPaneClosing\"", xaml, StringComparison.Ordinal);
        Assert.Contains("PaneOpened=\"OnNavigationPaneOpened\"", xaml, StringComparison.Ordinal);
        Assert.Contains("PaneOpening=\"OnNavigationPaneOpening\"", xaml, StringComparison.Ordinal);
        Assert.Contains("x:Name=\"ExpandedConnectionStatus\"", xaml, StringComparison.Ordinal);
        Assert.Contains("x:Name=\"ExpandedConnectionContent\"", xaml, StringComparison.Ordinal);
        var xamlDocument = System.Xml.Linq.XDocument.Parse(xaml);
        System.Xml.Linq.XElement expandedConnectionContent = xamlDocument.Descendants().Single(
            element => element.Attributes().Any(attribute =>
                attribute.Name.LocalName == "Name"
                && attribute.Value == "ExpandedConnectionContent"));
        Assert.Equal("Center", expandedConnectionContent.Attribute("VerticalAlignment")?.Value);
        Assert.All(expandedConnectionContent.Elements(), element =>
            Assert.Equal("Center", element.Attribute("VerticalAlignment")?.Value));
        System.Xml.Linq.XElement connectionText = expandedConnectionContent.Elements().Single(
            element => element.Name.LocalName == "TextBlock");
        Assert.Equal("0,2,0,0", connectionText.Attribute("Margin")?.Value);
        Assert.Equal("20", connectionText.Attribute("LineHeight")?.Value);
        Assert.Contains("OnNavigationPaneClosing", source, StringComparison.Ordinal);
        Assert.Contains("ShowCompactConnectionStatus();", source, StringComparison.Ordinal);
        Assert.Contains("OnNavigationPaneOpened", source, StringComparison.Ordinal);
        Assert.Contains("OnNavigationPaneOpening", source, StringComparison.Ordinal);
        Assert.Contains("ShowExpandedConnectionStatus();", source, StringComparison.Ordinal);
        Assert.Contains("ExpandedConnectionStatus.Opacity = 0", source, StringComparison.Ordinal);
        Assert.Contains("ExpandedConnectionStatus.Opacity = 1", source, StringComparison.Ordinal);
        Assert.Contains("<ScalarTransition Duration=\"0:0:0.16\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Background=\"{ThemeResource SideyAccentBackground12Brush}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Foreground=\"{ThemeResource SideyAccentForegroundBrush}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("<TitleBar", xaml, StringComparison.Ordinal);
        Assert.Contains("BackRequested=\"OnTitleBarBackRequested\"", xaml, StringComparison.Ordinal);
        Assert.Contains("PaneToggleRequested=\"OnTitleBarPaneToggleRequested\"", xaml, StringComparison.Ordinal);
        Assert.Contains("IsPaneToggleButtonVisible=\"False\"", xaml, StringComparison.Ordinal);
        Assert.Contains("MicaKind.Base", source, StringComparison.Ordinal);
        Assert.Contains("ExtendsContentIntoTitleBar = true", source, StringComparison.Ordinal);
        Assert.Contains("SetTitleBar(AppTitleBar)", source, StringComparison.Ordinal);
        Assert.Contains("_navigationHistory.Push", source, StringComparison.Ordinal);
        Assert.Contains("_navigationHistory.Pop", source, StringComparison.Ordinal);
        Assert.Contains("WindowsMinimumSizeController", source, StringComparison.Ordinal);
        Assert.DoesNotContain("AppWindow.Changed +=", source, StringComparison.Ordinal);
        Assert.Contains("GetMinMaxInfoMessage = 0x0024", minimumSize, StringComparison.Ordinal);
        Assert.Contains("SetWindowSubclass", minimumSize, StringComparison.Ordinal);
    }

    [Fact]
    public void ProfileAndGroupLayoutsRemainUsableAtTheResponsiveWindowSize()
    {
        var xaml = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml");
        var panel = ReadRepositoryFile("windows", "src", "Sidey.App", "Controls", "FixedColumnPanel.cs");

        Assert.Contains("ColumnCount=\"5\" ItemHeight=\"116\"", xaml, StringComparison.Ordinal);
        Assert.Equal(
            2,
            xaml.Split("ColumnCount=\"4\" ItemHeight=\"116\"", StringSplitOptions.None).Length - 1);
        Assert.Contains("ListViewItemBackgroundSelectedPointerOver", xaml, StringComparison.Ordinal);
        Assert.Contains("double itemWidth = finalSize.Width / columns", panel, StringComparison.Ordinal);
        Assert.Contains("int column = index % columns", panel, StringComparison.Ordinal);
        Assert.Contains("int row = index / columns", panel, StringComparison.Ordinal);
        Assert.Equal(
            3,
            xaml.Split("Width=\"{Binding ActualWidth, ElementName=ProfileCardContent}\"", StringSplitOptions.None).Length - 1);
        Assert.Contains("x:Name=\"BubbleSelector\"", xaml, StringComparison.Ordinal);
        Assert.Contains("x:Name=\"ThrowableSelector\"", xaml, StringComparison.Ordinal);
        Assert.Equal(2, xaml.Split("Background=\"Transparent\" BorderThickness=\"0\"", StringSplitOptions.None).Length - 1);
        Assert.Equal(3, xaml.Split("BorderThickness=\"1.5\"", StringSplitOptions.None).Length - 1);
        Assert.Contains(
            "HorizontalAlignment=\"Stretch\" VerticalAlignment=\"Center\" Padding=\"8\" Spacing=\"7\"",
            xaml,
            StringComparison.Ordinal);
        Assert.Equal(
            2,
            xaml.Split("HorizontalAlignment=\"Stretch\" VerticalAlignment=\"Center\" Spacing=\"7\"", StringSplitOptions.None).Length - 1);
        Assert.Equal(
            3,
            xaml.Split("ScrollViewer.VerticalScrollBarVisibility=\"Disabled\"", StringSplitOptions.None).Length - 1);
        Assert.Equal(
            2,
            xaml.Split("MinHeight=\"30\" HorizontalAlignment=\"Center\" Text=\"{Binding DisplayName}\"", StringSplitOptions.None).Length - 1);
        Assert.Contains("ItemsControl ItemsSource=\"{Binding Members}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Content=\"{i18n:I18n Key=groups.rename}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Command=\"{Binding RemoveCommand}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Visibility=\"{Binding CanRemove, Converter={StaticResource BooleanToVisibilityConverter}}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("SelectedIndex=\"{Binding SelectedEdgeIndex, Mode=TwoWay}\"", xaml, StringComparison.Ordinal);
        Assert.DoesNotContain("월드 배치 적용", xaml, StringComparison.Ordinal);
    }

    [Fact]
    public void StoreUsesFiveColumnSearchableCardsAndLockedDetailPurchase()
    {
        var xaml = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml");
        var viewModel = ReadRepositoryFile(
            "windows", "src", "Sidey.Presentation", "ViewModels", "MainWindowViewModel.cs");
        var productViewModel = ReadRepositoryFile(
            "windows", "src", "Sidey.Presentation", "ViewModels", "StoreProductPreviewViewModel.cs");
        var buildProperties = ReadRepositoryFile("windows", "Directory.Build.props");

        Assert.Contains("ItemsSource=\"{Binding VisibleStoreProducts}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("SelectedStoreKindIndex", viewModel, StringComparison.Ordinal);
        Assert.Contains("SelectedStoreSortIndex", xaml, StringComparison.Ordinal);
        Assert.Contains("HidesOwnedStoreProducts", xaml, StringComparison.Ordinal);
        Assert.Contains("StoreSearchText", xaml, StringComparison.Ordinal);
        Assert.Contains("<SelectorBar", xaml, StringComparison.Ordinal);
        Assert.Contains("OnStoreKindSelectionChanged", xaml, StringComparison.Ordinal);
        Assert.DoesNotContain("<TabView", xaml, StringComparison.Ordinal);
        string mainWindowSource = ReadRepositoryFile(
            "windows", "src", "Sidey.App", "MainWindow.xaml.cs");
        Assert.Contains("AnimatePageRefresh", mainWindowSource, StringComparison.Ordinal);
        Assert.Contains("AnimateSiblingPage", mainWindowSource, StringComparison.Ordinal);
        Assert.Contains("new UISettings().AnimationsEnabled", mainWindowSource, StringComparison.Ordinal);
        Assert.Contains("<UniformGridLayout", xaml, StringComparison.Ordinal);
        Assert.Contains("MaximumRowsOrColumns=\"5\"", xaml, StringComparison.Ordinal);
        Assert.Contains("x:Name=\"StoreFilterToggle\"", xaml, StringComparison.Ordinal);
        Assert.Contains("x:Name=\"StoreFilterPanel\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Visibility=\"Collapsed\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Style=\"{StaticResource SideySettingsCardStyle}\"", xaml, StringComparison.Ordinal);
        Assert.Contains(
            "<controls:StoreProductArtwork",
            xaml,
            StringComparison.Ordinal);
        Assert.DoesNotContain("Text=\"{Binding Description}\"", xaml, StringComparison.Ordinal);
        Assert.DoesNotContain("Command=\"{Binding ActionCommand}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Command=\"{Binding PreviewCommand}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("StorePreviewStage", mainWindowSource, StringComparison.Ordinal);
        Assert.Contains("IsPrimaryButtonEnabled = false", mainWindowSource, StringComparison.Ordinal);
        string artwork = ReadRepositoryFile(
            "windows", "src", "Sidey.App", "Controls", "StoreProductArtwork.xaml");
        string artworkSource = ReadRepositoryFile(
            "windows", "src", "Sidey.App", "Controls", "StoreProductArtwork.xaml.cs");
        string imageLoader = ReadRepositoryFile(
            "windows", "src", "Sidey.App", "Controls", "StorePreviewImageLoader.cs");
        string previewStage = ReadRepositoryFile(
            "windows", "src", "Sidey.App", "Controls", "StorePreviewStage.xaml");
        string previewStageSource = ReadRepositoryFile(
            "windows", "src", "Sidey.App", "Controls", "StorePreviewStage.xaml.cs");
        Assert.Contains("Loaded=\"OnLoaded\"", artwork, StringComparison.Ordinal);
        Assert.Contains("x:Name=\"PreviewImage\"", artwork, StringComparison.Ordinal);
        Assert.DoesNotContain("CanvasControl", artwork, StringComparison.Ordinal);
        Assert.Contains("LoadFrameAsync", artworkSource, StringComparison.Ordinal);
        Assert.Contains("CannonEmitterImage", artwork, StringComparison.Ordinal);
        Assert.Contains("decoration.png", artworkSource, StringComparison.Ordinal);
        Assert.DoesNotContain("preview.png", artworkSource, StringComparison.Ordinal);
        Assert.Contains("double pointSize = ActualHeight > 64 ? 82 : 56", artworkSource, StringComparison.Ordinal);
        Assert.Contains("Height=\"28\"", artwork, StringComparison.Ordinal);
        Assert.Contains("BitmapInterpolationMode.NearestNeighbor", imageLoader, StringComparison.Ordinal);
        Assert.Contains("ConditionalWeakTable<ImageSource, SoftwareBitmap>", imageLoader, StringComparison.Ordinal);
        Assert.Contains("BitmapLifetimes.Add(source, bitmap)", imageLoader, StringComparison.Ordinal);
        Assert.Contains("CardBackgroundFillColorDefaultBrush", previewStage, StringComparison.Ordinal);
        Assert.DoesNotContain("Background=\"#12141B\"", previewStage, StringComparison.Ordinal);
        Assert.Contains("Width=\"540\"", previewStage, StringComparison.Ordinal);
        Assert.Contains("Height=\"280\"", previewStage, StringComparison.Ordinal);
        Assert.Contains("x:Name=\"PlatformCanvas\"", previewStage, StringComparison.Ordinal);
        Assert.Contains("x:Name=\"BubbleTail\"", previewStage, StringComparison.Ordinal);
        Assert.Contains("UpdateBubble", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("UpdateThrow", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("PixelMovementSimulation.Step", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("WalkFrameSeconds", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("IdleFrameSeconds = 0.55", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("TypingFrameSeconds = 0.35", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("ThrowActionSeconds = 0.4", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("ThrowReleaseSeconds = 0.2", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("HitActionSeconds = 0.44", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("ImpactSeconds = 0.24", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("ProjectileRotationFrameSeconds = 0.083", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("distance / 1600d", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("RenderedCharacterSize = 72", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("RenderedFootBaseline = 9", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("ProjectileSize = 48", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("ProjectilePathY = PlatformTop", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("controlY = ProjectilePathY - (arcHeight * 2d)", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("ImpactSize = 64", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("EmitterSize = 72", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("BubbleTypingWidth = 63", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("BubbleMessageFontSize = 16.5", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("TurnFromWall", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("UpdateFacing", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("ApplyCharacterPose", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("SetImageSource", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("BuildCharacterLayers", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("ShowCharacterLayer", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("movementFrames.Concat(actionFrames)", previewStageSource, StringComparison.Ordinal);
        Assert.DoesNotContain("x:Name=\"LeftCharacter\"", previewStage, StringComparison.Ordinal);
        Assert.DoesNotContain("Stroke=\"#2914171F\"", previewStage, StringComparison.Ordinal);
        Assert.DoesNotContain("double bubbleWidth = typing ? 54 : 142", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("Math.Clamp(Math.Ceiling(BubbleText.DesiredSize.Width), 42, 330)", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("senderCenter - visualLeft", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("Width=\"6\" Height=\"6\"", previewStage, StringComparison.Ordinal);
        Assert.DoesNotContain("x:Name=\"LeftNameplate\" Width=\"70\"", previewStage, StringComparison.Ordinal);
        Assert.Contains("x:Name=\"SparkleCanvas\"", previewStage, StringComparison.Ordinal);
        Assert.Contains("x:Name=\"ImpactImage\"", previewStage, StringComparison.Ordinal);
        Assert.Contains("EmitterScale.ScaleX = leftToRight ? 1 : -1", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("throw_hit.png", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("projectileFrames = new ImageSource[12]", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("StartAnimation", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("StopAnimation", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("_timer.Start()", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("BeginPresentation", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("EndPresentation", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("await InitializeAsync(presentationGeneration, _lifetimeToken)", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("IsCurrentPresentation(presentationGeneration) && _resourcesLoaded", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("if (!_isPresented || !_resourcesLoaded)", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("Task loadTask = _loadTask ?? StartResourceLoad", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("store-preview-load-cancelled", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("_lifetime.Token", mainWindowSource, StringComparison.Ordinal);
        Assert.DoesNotContain("dialog.Opened +=", mainWindowSource, StringComparison.Ordinal);
        Assert.Contains("dialog.Closing +=", mainWindowSource, StringComparison.Ordinal);
        Assert.Contains("previewStage.BeginPresentation()", mainWindowSource, StringComparison.Ordinal);
        Assert.Contains("previewStage?.EndPresentation()", mainWindowSource, StringComparison.Ordinal);
        Assert.Contains("_storePreviewDialogOpen", mainWindowSource, StringComparison.Ordinal);
        Assert.Contains("_isPresented", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("CancelPendingLoad()", artworkSource, StringComparison.Ordinal);
        Assert.Contains("CancelPendingLoad()", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("CancellationToken cancellationToken = default", imageLoader, StringComparison.Ordinal);
        Assert.Contains("ThrowIfLoadExpired", previewStageSource, StringComparison.Ordinal);
        Assert.Contains("cancellationToken.ThrowIfCancellationRequested()", imageLoader, StringComparison.Ordinal);
        Assert.DoesNotContain("storyboard.Completed +=", mainWindowSource, StringComparison.Ordinal);
        Assert.True(CountOccurrences(xaml, "Glyph=\"&#xE73E;\"") >= 3);
        Assert.Contains("bool isActionEnabled = commerceEnabled", productViewModel, StringComparison.Ordinal);
        Assert.Contains("IsPreviewOnlyVisible = !commerceEnabled", productViewModel, StringComparison.Ordinal);
        Assert.Contains("'$(Configuration)' == 'Debug'", buildProperties, StringComparison.Ordinal);
        Assert.Contains("SIDEY_DEVELOPMENT_COMMERCE", buildProperties, StringComparison.Ordinal);
        Assert.Contains("character_starlight_upalupa", viewModel, StringComparison.Ordinal);
        Assert.DoesNotContain("PurchaseCommand", xaml, StringComparison.Ordinal);
    }

    [Fact]
    public void CharacterPreviewsUseNearestNeighborRenderingLikeMac()
    {
        var main = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml");
        var onboarding = ReadRepositoryFile(
            "windows", "src", "Sidey.App", "OnboardingWindow.xaml");
        var history = ReadRepositoryFile("windows", "src", "Sidey.App", "HistoryWindow.xaml");
        var preview = ReadRepositoryFile(
            "windows", "src", "Sidey.App", "Controls", "PixelCharacterPreview.xaml.cs");
        var loader = ReadRepositoryFile(
            "windows", "src", "Sidey.App", "Controls", "StorePreviewImageLoader.cs");

        Assert.Equal(2, CountOccurrences(main, "<controls:PixelCharacterPreview"));
        Assert.Contains("<controls:PixelCharacterPreview", onboarding, StringComparison.Ordinal);
        Assert.Contains("<controls:PixelCharacterPreview", history, StringComparison.Ordinal);
        Assert.DoesNotContain("CharacterImageConverter", main, StringComparison.Ordinal);
        Assert.DoesNotContain("CharacterImageConverter", onboarding, StringComparison.Ordinal);
        Assert.DoesNotContain("CharacterImageConverter", history, StringComparison.Ordinal);
        Assert.Contains("StorePreviewImageLoader.LoadFrameAsync", preview, StringComparison.Ordinal);
        Assert.Contains("BitmapInterpolationMode.NearestNeighbor", loader, StringComparison.Ordinal);
        Assert.Contains("checked((uint)definition.FrameWidth)", preview, StringComparison.Ordinal);
        Assert.Contains("checked((uint)definition.FrameHeight)", preview, StringComparison.Ordinal);
    }

    [Fact]
    public void GroupManagementShowsTargetProgressAndConfirmsDestructiveActions()
    {
        var app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");
        var coordinator = ReadRepositoryFile("windows", "src", "Sidey.App", "AppCoordinator.cs");
        var xaml = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml");
        var window = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml.cs");
        var viewModel = ReadRepositoryFile(
            "windows", "src", "Sidey.Presentation", "ViewModels", "MainWindowViewModel.cs");

        Assert.Contains("IsSwitching", xaml, StringComparison.Ordinal);
        Assert.Contains("JoinActionText", xaml, StringComparison.Ordinal);
        Assert.Contains("CreateRoomActionText", xaml, StringComparison.Ordinal);
        Assert.Contains("JoinRoomActionText", xaml, StringComparison.Ordinal);
        Assert.Contains("AreOwnerActionsEnabled", xaml, StringComparison.Ordinal);
        Assert.Contains("Margin=\"0,0,0,16\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Command=\"{Binding LeaveCommand}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("ConfirmRoomLeaveAsync(room.Name, isOwner)", viewModel, StringComparison.Ordinal);
        Assert.Contains("GroupOperation.Mutating", coordinator, StringComparison.Ordinal);
        Assert.Contains("RunRoomMutationAsync", coordinator, StringComparison.Ordinal);
        Assert.Contains("SwitchingRoomId == room.Id", viewModel, StringComparison.Ordinal);
        Assert.Contains("ConfirmMemberRemovalAsync(member.Nickname)", viewModel, StringComparison.Ordinal);
        Assert.Contains("impactDialog", window, StringComparison.Ordinal);
        Assert.Contains("finalDialog", window, StringComparison.Ordinal);
        Assert.Contains("NoticeRaised", viewModel, StringComparison.Ordinal);
        Assert.Contains("MainWindow mainWindow = EnsureMainWindow()", app, StringComparison.Ordinal);
        Assert.Contains("ShowPrimaryWindow()", app, StringComparison.Ordinal);
        Assert.DoesNotContain("ToastNotification", app, StringComparison.Ordinal);
        Assert.DoesNotContain("AppNotification", app, StringComparison.Ordinal);
        Assert.DoesNotContain("ToastNotification", window, StringComparison.Ordinal);
    }

    [Fact]
    public void DozeAnimationMatchesMacTimingOpacityAndDistance()
    {
        var source = ReadRepositoryFile("windows", "src", "Sidey.Overlay", "LayeredPixelWorldRenderer.cs");
        var textVisuals = ReadRepositoryFile("windows", "src", "Sidey.Overlay", "PixelTextVisualCache.cs");

        Assert.Contains("DozeRestingOpacity = 0.55d", source, StringComparison.Ordinal);
        Assert.Contains("DozeFloatingDistanceDip = 3d", source, StringComparison.Ordinal);
        Assert.Contains("var phase = tick % FramesPerSecond", source, StringComparison.Ordinal);
        Assert.Contains("FloatDozeTowardInterior", source, StringComparison.Ordinal);
        Assert.Contains("_dozeStartedAt", source, StringComparison.Ordinal);
        Assert.Contains("DozeFontSizeDip = 14f", textVisuals, StringComparison.Ordinal);
        Assert.Contains("DozeOutlineWidthDip = 2f", textVisuals, StringComparison.Ordinal);
        Assert.Contains("Color.FromArgb(255, 255, 149, 0)", textVisuals, StringComparison.Ordinal);
        Assert.Contains("Color.FromArgb(235, 20, 18, 15)", textVisuals, StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsBuildUsesTheSideyAppIcon()
    {
        var project = ReadRepositoryFile("windows", "src", "Sidey.App", "Sidey.App.csproj");
        var tray = ReadRepositoryFile("windows", "src", "Sidey.Platform.Windows", "TrayIconService.cs");

        Assert.Contains("<ApplicationIcon>Assets\\Icons\\SideyAppIcon.ico</ApplicationIcon>", project, StringComparison.Ordinal);
        Assert.Contains("<None Update=\"Assets\\Icons\\*\">", project, StringComparison.Ordinal);
        Assert.Contains("Assets", tray, StringComparison.Ordinal);
        Assert.Contains("Icons", tray, StringComparison.Ordinal);
        Assert.Contains("SideyAppIcon.ico", tray, StringComparison.Ordinal);

        var icon = File.ReadAllBytes(RepositoryPath(
            "windows", "src", "Sidey.App", "Assets", "Icons", "SideyAppIcon.ico"));
        Assert.Equal(0, BitConverter.ToUInt16(icon, 0));
        Assert.Equal(1, BitConverter.ToUInt16(icon, 2));
        var imageCount = BitConverter.ToUInt16(icon, 4);
        Assert.Equal(9, imageCount);
        var embeddedSizes = new List<int>();
        for (var index = 0; index < imageCount; index++)
        {
            var entryOffset = 6 + (index * 16);
            embeddedSizes.Add(icon[entryOffset] == 0 ? 256 : icon[entryOffset]);
            var imageLength = BitConverter.ToUInt32(icon, entryOffset + 8);
            var imageOffset = BitConverter.ToUInt32(icon, entryOffset + 12);
            Assert.True(imageLength > 8);
            Assert.True(imageOffset + imageLength <= icon.Length);
            Assert.Equal(0x89, icon[imageOffset]);
            Assert.Equal((byte)'P', icon[imageOffset + 1]);
            Assert.Equal((byte)'N', icon[imageOffset + 2]);
            Assert.Equal((byte)'G', icon[imageOffset + 3]);
        }
        Assert.Equal([16, 20, 24, 32, 40, 48, 64, 128, 256], embeddedSizes);

        foreach (var size in embeddedSizes)
        {
            Assert.True(File.Exists(RepositoryPath(
                "windows", "src", "Sidey.App", "Assets", "Icons", $"SideyAppIcon-{size}.png")));
        }

        Assert.True(File.Exists(RepositoryPath(
            "windows", "src", "Sidey.App", "Assets", "Icons", "SideyAppIcon.png")));
    }

    [Fact]
    public void TrayUsesTheStandardWindowsHoverTooltip()
    {
        var tray = ReadRepositoryFile(
            "windows", "src", "Sidey.Platform.Windows", "TrayIconService.cs");

        Assert.Contains("NotifyIconShowTip = 0x80", tray, StringComparison.Ordinal);
        Assert.Contains("NotifyIconTip | NotifyIconShowTip", tray, StringComparison.Ordinal);
        Assert.Contains("tray.unreadTooltip", tray, StringComparison.Ordinal);
        Assert.Contains("_state.UnreadCount > 0", tray, StringComparison.Ordinal);
        Assert.Contains("_unreadIcon", tray, StringComparison.Ordinal);
        Assert.Contains("TrayUnreadBadgeRenderer.Apply", tray, StringComparison.Ordinal);
        Assert.Contains("mouseMessage is 0x0202 or 0x0203 or 0x0405", tray, StringComparison.Ordinal);
        Assert.Contains("CommandInvoked?.Invoke(TrayCommand.Open)", tray, StringComparison.Ordinal);
        Assert.DoesNotContain("SetMenuDefaultItem", tray, StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsReleaseManifestIsTheSingleCheckedInPublicSource()
    {
        using var document = System.Text.Json.JsonDocument.Parse(
            File.ReadAllBytes(RepositoryPath("release", "windows.json")));
        var root = document.RootElement;

        Assert.Equal(1, root.GetProperty("schema").GetInt32());
        Assert.Equal("windows", root.GetProperty("platform").GetString());
        Assert.Equal("production", root.GetProperty("channel").GetString());
        var publicVersion = Version.Parse(root.GetProperty("version").GetString()!);
        var sourceVersion = Version.Parse(WindowsUpdateService.CurrentVersion);
        Assert.True(publicVersion.CompareTo(sourceVersion) <= 0);
        Assert.False(File.Exists(RepositoryPath("website", "windows-latest.json")));
        Assert.False(File.Exists(RepositoryPath("website", "windows", "update.json")));

        var publisher = ReadRepositoryFile("scripts", "website", "prepare-release-metadata.ps1");
        Assert.Contains("windows-latest.json", publisher, StringComparison.Ordinal);
        Assert.Contains("windows/update.json", publisher, StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsReleaseUsesAPlatformScopedTag()
    {
        var ciWorkflow = ReadRepositoryFile(".github", "workflows", "windows.yml");
        var releaseWorkflow = ReadRepositoryFile(".github", "workflows", "windows-release.yml");
        var metadata = ReadRepositoryFile("scripts", "verify_release_consistency.py");
        var verifier = ReadRepositoryFile("scripts", "windows", "verify-release.ps1");

        Assert.DoesNotContain("tags:", ciWorkflow, StringComparison.Ordinal);
        Assert.DoesNotContain("tags:", releaseWorkflow, StringComparison.Ordinal);
        Assert.Contains("tag = f\"windows-v{version}\"", metadata, StringComparison.Ordinal);
        Assert.DoesNotContain("refs/tags/v", releaseWorkflow, StringComparison.Ordinal);
        Assert.Contains("$tag = \"windows-v$Version\"", verifier, StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsPackagingHasOneManualVerifiedReleaseEntryPoint()
    {
        var ciWorkflow = ReadRepositoryFile(".github", "workflows", "windows.yml");
        var workflow = ReadRepositoryFile(".github", "workflows", "windows-release.yml");

        Assert.DoesNotContain("workflow_dispatch:", ciWorkflow, StringComparison.Ordinal);
        Assert.Contains("workflow_dispatch:", workflow, StringComparison.Ordinal);
        Assert.Contains("confirm_version:", workflow, StringComparison.Ordinal);
        Assert.Contains("validate:", workflow, StringComparison.Ordinal);
        Assert.Contains("--draft", workflow, StringComparison.Ordinal);
        Assert.Contains("gh release download", workflow, StringComparison.Ordinal);
        Assert.Contains("Get-FileHash", workflow, StringComparison.Ordinal);
        Assert.Contains("gh release edit $tag --draft=false", workflow, StringComparison.Ordinal);
        Assert.Contains("uses: ./.github/workflows/pages.yml", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("--prerelease", workflow, StringComparison.Ordinal);
        Assert.Contains("winget install NSIS.NSIS", workflow, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("--version 3.12", workflow, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("SelfSigned", workflow, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void UpdateDesignTestUsesTheArtifactVersionWithoutLoweringReleaseSources()
    {
        var adapter = ReadRepositoryFile(
            "windows", "src", "Sidey.App", "WindowsUpdateServiceAdapter.cs");
        var script = ReadRepositoryFile(
            "scripts", "windows", "start-update-design-test.ps1");

        Assert.Contains(
            "typeof(App).Assembly.GetName().Version?.ToString(3)",
            adapter,
            StringComparison.Ordinal);
        Assert.Contains("-p:Version=$TestVersion", script, StringComparison.Ordinal);
        Assert.Contains("-p:FileVersion=$TestVersion.0", script, StringComparison.Ordinal);
        Assert.Contains("-p:AssemblyVersion=$TestVersion.0", script, StringComparison.Ordinal);
        Assert.Contains("[Version]$TestVersion -ge $publicVersion", script, StringComparison.Ordinal);
    }

    [Fact]
    public void MissingWindowsUpdateManifestHasAnActionableMessage()
    {
        var source = ReadRepositoryFile(
            "windows", "src", "Sidey.Platform.Windows", "WindowsUpdateService.cs");

        Assert.Contains("windows-latest.json", source, StringComparison.Ordinal);
        Assert.Contains("HttpStatusCode.NotFound", source, StringComparison.Ordinal);
        Assert.Contains("update.notPublished", source, StringComparison.Ordinal);
    }

    [Fact]
    public void UpdateCheckStartsOncePerProcessInsteadOfWhenSettingsOpens()
    {
        var app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");
        var mainWindow = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml.cs");

        Assert.Equal(2, CountOccurrences(app, "StartStartupUpdateCheck()"));
        Assert.Contains("_startupUpdateCheckStarted = true", app, StringComparison.Ordinal);
        Assert.Contains("startup-update-checked", app, StringComparison.Ordinal);
        Assert.DoesNotContain("CheckForUpdates();\n        SideyWindowActivation", mainWindow, StringComparison.Ordinal);
    }

    private static int CountOccurrences(string value, string search) =>
        value.Split(search, StringSplitOptions.None).Length - 1;

    private static string ReadRepositoryFile(params string[] pathSegments)
        => File.ReadAllText(RepositoryPath(pathSegments));

    private static string RepositoryPath(params string[] pathSegments)
    {
        var root = new DirectoryInfo(AppContext.BaseDirectory);
        while (root is not null && !Directory.Exists(Path.Combine(root.FullName, "windows", "src")))
        {
            root = root.Parent;
        }

        Assert.NotNull(root);
        return Path.Combine([root!.FullName, .. pathSegments]);
    }
}
