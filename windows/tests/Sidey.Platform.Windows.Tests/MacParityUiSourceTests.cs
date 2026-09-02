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
        Assert.Contains("OnboardingCompleted = _state.Preferences.OnboardingCompleted", coordinator, StringComparison.Ordinal);
        Assert.Contains("|| (snapshot.Profile is not null && snapshot.Rooms.Count > 0)", coordinator, StringComparison.Ordinal);
    }

    [Fact]
    public void CompletedLaunchStaysInTrayAndSettingsCloseHidesTheWindow()
    {
        var app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");
        var mainWindow = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml.cs");

        Assert.Contains("if (!_coordinator.State.Preferences.OnboardingCompleted)", app, StringComparison.Ordinal);
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
    }

    [Fact]
    public void DebugPreviewReplaysOnboardingWithoutResettingPreferencesOrCredentials()
    {
        var app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");
        var viewModel = ReadRepositoryFile(
            "windows", "src", "Sidey.Presentation", "ViewModels", "OnboardingViewModel.cs");

        Assert.Contains("#if DEBUG", app, StringComparison.Ordinal);
        Assert.Contains("--onboarding-preview", app, StringComparison.Ordinal);
        Assert.Contains("else if (onboardingPreview)", app, StringComparison.Ordinal);
        Assert.Contains("if (IsPreviewMode)", viewModel, StringComparison.Ordinal);
        Assert.Contains("onboarding.previewConnection", viewModel, StringComparison.Ordinal);
    }

    [Fact]
    public void SecondaryDebugLaunchRequestsPreviewFromThePrimaryInstance()
    {
        var app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");
        var guard = ReadRepositoryFile(
            "windows", "src", "Sidey.App", "SingleInstanceGuard.cs");

        Assert.Contains("SingleInstanceRequest.OnboardingPreview", app, StringComparison.Ordinal);
        Assert.Contains("_singleInstance.Signal(request)", app, StringComparison.Ordinal);
        Assert.Contains("RequestOnboardingPreview", app, StringComparison.Ordinal);
        Assert.Contains("StartListening", guard, StringComparison.Ordinal);
        Assert.Contains("onboarding-preview", guard, StringComparison.Ordinal);
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
        var historyXaml = ReadRepositoryFile("windows", "src", "Sidey.App", "HistoryWindow.xaml");
        var historyViewModel = ReadRepositoryFile(
            "windows", "src", "Sidey.Presentation", "ViewModels", "HistoryWindowViewModel.cs");
        var gateway = ReadRepositoryFile("windows", "src", "Sidey.Infrastructure", "SupabaseBackendGateway.cs");

        Assert.Contains("tray.activeGroup", tray, StringComparison.Ordinal);
        Assert.Contains("tray.history", tray, StringComparison.Ordinal);
        Assert.Contains("tray.store", tray, StringComparison.Ordinal);
        Assert.Contains("tray.exit", tray, StringComparison.Ordinal);
        Assert.Contains("Text=\"{Binding EmptyMessage}\"", historyXaml, StringComparison.Ordinal);
        Assert.Contains("Text=\"{Binding EmptyDescription}\"", historyXaml, StringComparison.Ordinal);
        Assert.Contains("history.empty", historyViewModel, StringComparison.Ordinal);
        Assert.Contains("history.emptyDescription", historyViewModel, StringComparison.Ordinal);
        Assert.DoesNotContain("새로 고침", historyXaml, StringComparison.Ordinal);
        Assert.Contains("ToLocalTime()", historyViewModel, StringComparison.Ordinal);
        Assert.Contains("ToString(\"g\"", historyViewModel, StringComparison.Ordinal);
        Assert.Contains("order=created_at.desc,id.desc", gateway, StringComparison.Ordinal);
        Assert.Contains("created_at.lt.", gateway, StringComparison.Ordinal);
        Assert.Contains("id.lt.", gateway, StringComparison.Ordinal);
        Assert.Contains("boundedLimit + 1", gateway, StringComparison.Ordinal);
        Assert.Contains("MessageLedger.ConfirmedRetention", gateway, StringComparison.Ordinal);
        Assert.Contains(
            "(!isActiveRoom || _state.Preferences.QuietMode)",
            ReadRepositoryFile("windows", "src", "Sidey.App", "AppCoordinator.cs"),
            StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsDoesNotAddSystemNotificationsAbsentFromMac()
    {
        var app = ReadRepositoryFile("windows", "src", "Sidey.App", "App.xaml.cs");
        var tray = ReadRepositoryFile("windows", "src", "Sidey.Platform.Windows", "TrayIconService.cs");

        Assert.DoesNotContain("ShowStateNotification", app, StringComparison.Ordinal);
        Assert.DoesNotContain("public void Notify", tray, StringComparison.Ordinal);
    }

    [Fact]
    public void RealtimeSyncPrecedesOverlayAndPresenceColorsMatchMacV103()
    {
        var coordinator = ReadRepositoryFile("windows", "src", "Sidey.App", "AppCoordinator.cs");
        var visuals = ReadRepositoryFile("windows", "src", "Sidey.Overlay", "PixelTextVisualCache.cs");
        var renderer = ReadRepositoryFile("windows", "src", "Sidey.Overlay", "LayeredPixelWorldRenderer.cs");

        Assert.Contains("&& _state.Connected", coordinator, StringComparison.Ordinal);
        Assert.Contains("private void SetRealtimeConnected(bool connected)", coordinator, StringComparison.Ordinal);
        Assert.DoesNotContain("_state = _state with { Connected = true", coordinator, StringComparison.Ordinal);
        Assert.Contains("PresenceState.Offline => Color.FromArgb(255, 255, 59, 48)", visuals, StringComparison.Ordinal);
        Assert.Contains("PresenceState.Reconnecting => Color.FromArgb(255, 142, 142, 147)", visuals, StringComparison.Ordinal);
        Assert.Contains("desaturate: node.Member.Presence == PresenceState.Offline", renderer, StringComparison.Ordinal);
    }

    [Fact]
    public void DevelopmentUpdaterWatchesAtTheStructuredDeploymentRoot()
    {
        var source = ReadRepositoryFile("windows", "src", "Sidey.App", "DevelopmentUpdateService.cs");

        Assert.Contains("SideyDeploymentPaths.DeploymentRoot()", source, StringComparison.Ordinal);
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
        Assert.Contains("FocusAttemptCount = 3", source, StringComparison.Ordinal);
        Assert.Contains("MessageInput.Focus(FocusState.Programmatic)", source, StringComparison.Ordinal);
        Assert.Contains("WindowActivationState.Deactivated", source, StringComparison.Ordinal);
        Assert.Contains("HideComposer();", source, StringComparison.Ordinal);
        Assert.Contains("ViewModel.OnHidden();", source, StringComparison.Ordinal);
        Assert.Contains("CancelAutoClose();", viewModel, StringComparison.Ordinal);
        Assert.Contains("TimeSpan.FromSeconds(5)", viewModel, StringComparison.Ordinal);
    }

    [Fact]
    public void MessageBubblesMatchMacWidthTypographyAndInsets()
    {
        var source = ReadRepositoryFile(
            "windows", "src", "Sidey.Overlay", "PixelTextVisualCache.cs");
        var renderer = ReadRepositoryFile(
            "windows", "src", "Sidey.Overlay", "LayeredPixelWorldRenderer.cs");

        Assert.Contains("BubbleMaximumWidthDip = 220f", source, StringComparison.Ordinal);
        Assert.Contains("BubbleMinimumWidthDip = 28f", source, StringComparison.Ordinal);
        Assert.Contains("BubbleHorizontalPaddingDip = 8f", source, StringComparison.Ordinal);
        Assert.Contains("BubbleVerticalPaddingDip = 7f", source, StringComparison.Ordinal);
        Assert.Contains("BubbleFontSizeDip = 10.5f", source, StringComparison.Ordinal);
        Assert.Contains("var (width, height) = MeasureBubble(body)", source, StringComparison.Ordinal);
        Assert.Contains("naturalLayout.LayoutBoundsIncludingTrailingWhitespace", source, StringComparison.Ordinal);
        Assert.Contains("wrappedLayout.LayoutBoundsIncludingTrailingWhitespace", source, StringComparison.Ordinal);
        Assert.DoesNotContain("var bounds = layout.DrawBounds", source, StringComparison.Ordinal);
        Assert.Contains("var halfWidth = tangentWidth / 2d", renderer, StringComparison.Ordinal);
        Assert.DoesNotContain("bubble.Body.Length * 8d", renderer, StringComparison.Ordinal);
    }

    [Fact]
    public void AppSettingsExposeMacTitlesAndDescriptions()
    {
        var xaml = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml");
        var source = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml.cs");

        Assert.Contains("PaneTitle=\"SIDEY\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Key=settings.overlayDescription", xaml, StringComparison.Ordinal);
        Assert.Contains("Key=settings.quietModeDescription", xaml, StringComparison.Ordinal);
        Assert.Contains("Key=settings.offlineMembersDescription", xaml, StringComparison.Ordinal);
        Assert.Contains("Key=settings.monitorDescription", xaml, StringComparison.Ordinal);
        Assert.Contains("NavigationViewContentBackground\" Color=\"Transparent", xaml, StringComparison.Ordinal);
        Assert.Contains("HorizontalAlignment=\"Right\"", xaml, StringComparison.Ordinal);
        Assert.Contains("OffContent=\"\" OnContent=\"\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Width=\"48\" MinWidth=\"0\"", xaml, StringComparison.Ordinal);
        Assert.Contains("MicaKind.Base", source, StringComparison.Ordinal);
        Assert.Contains("_minimumWindowSize = size;", source, StringComparison.Ordinal);
    }

    [Fact]
    public void ProfileAndGroupLayoutsRemainUsableAtTheResponsiveWindowSize()
    {
        var xaml = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml");
        var source = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml.cs");

        Assert.Contains("MaximumRowsOrColumns=\"5\"", xaml, StringComparison.Ordinal);
        Assert.Contains("(CharacterSelector.ActualWidth - 24d) / 5d", source, StringComparison.Ordinal);
        Assert.Contains("ItemsControl ItemsSource=\"{Binding Members}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Content=\"{i18n:I18n Key=groups.rename}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Command=\"{Binding RemoveCommand}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Visibility=\"{Binding CanRemove, Converter={StaticResource BooleanToVisibilityConverter}}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("SelectedIndex=\"{Binding SelectedEdgeIndex, Mode=TwoWay}\"", xaml, StringComparison.Ordinal);
        Assert.DoesNotContain("월드 배치 적용", xaml, StringComparison.Ordinal);
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
    }

    [Fact]
    public void WindowsUpdateManifestsArePublishedWithTheWebsite()
    {
        AssertWindowsManifest("website", "windows-latest.json");
        AssertWindowsManifest("website", "windows", "update.json");
    }

    [Fact]
    public void WindowsReleaseUsesAPlatformScopedTag()
    {
        var workflow = ReadRepositoryFile(".github", "workflows", "windows.yml");
        var verifier = ReadRepositoryFile("scripts", "windows", "verify-release.ps1");

        Assert.Contains("tags: ['windows-v*']", workflow, StringComparison.Ordinal);
        Assert.Contains("$expectedTag = \"windows-v$version\"", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("refs/tags/v", workflow, StringComparison.Ordinal);
        Assert.Contains("$tag = \"windows-v$Version\"", verifier, StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsPackagingRunsOnlyForManualOrTaggedBuilds()
    {
        var workflow = ReadRepositoryFile(".github", "workflows", "windows.yml");

        Assert.Contains("validate:", workflow, StringComparison.Ordinal);
        Assert.Contains("github.event_name == 'workflow_dispatch'", workflow, StringComparison.Ordinal);
        Assert.Contains("startsWith(github.ref, 'refs/tags/windows-v')", workflow, StringComparison.Ordinal);
        Assert.Contains("SIDEY-Windows-x64-v${{ needs.validate.outputs.version }}.msi", workflow, StringComparison.Ordinal);
        Assert.Contains("docs/releases/windows-v$version.md", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("Upload test results", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("Upload CI-only MSI", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("--prerelease", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("Setup.exe", workflow, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(".sha256", workflow, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("SelfSigned", workflow, StringComparison.OrdinalIgnoreCase);
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

    private static void AssertWindowsManifest(params string[] pathSegments)
    {
        using var document = System.Text.Json.JsonDocument.Parse(
            File.ReadAllBytes(RepositoryPath(pathSegments)));
        var root = document.RootElement;

        string channel = root.GetProperty("channel").GetString()!;
        Assert.Contains(channel, new[] { "alpha", "production" });
        string version = root.GetProperty("version").GetString()!;
        Assert.False(WindowsUpdateService.IsNewerVersion(
            version,
            WindowsUpdateService.CurrentVersion));
        Assert.Equal(
            $"windows-v{version}",
            root.GetProperty("tag").GetString());
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
