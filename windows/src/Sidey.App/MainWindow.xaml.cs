using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sidey.Core.Domain;
using Sidey.Platform.Windows;

namespace Sidey.App;

public sealed partial class MainWindow : Window
{
    private readonly AppCoordinator _coordinator;
    private readonly WindowsUpdateService _updates = new();
    private CoordinatorState _state = CoordinatorState.Initial;
    private bool _applyingState;
    private bool _allowClose;
#if DEBUG
    private readonly DispatcherTimer _validationMetricsTimer = new()
    {
        Interval = TimeSpan.FromSeconds(1),
    };
#endif

    public MainWindow(AppCoordinator coordinator)
    {
        _coordinator = coordinator ?? throw new ArgumentNullException(nameof(coordinator));
        InitializeComponent();
        Title = "SIDEY";
        CharacterSelector.ItemsSource = PixelCharacterCatalog.All;
        CharacterSelector.SelectedValue = PixelCharacterCatalog.FallbackId;
        MonitorSelector.ItemsSource = _coordinator.GetMonitors();
        RootNavigation.SelectedItem = RootNavigation.MenuItems[0];
        AppWindow.Closing += OnAppWindowClosing;
#if DEBUG
        _validationMetricsTimer.Tick += (_, _) => RefreshValidationMetrics();
        _validationMetricsTimer.Start();
#endif
        ApplyState(coordinator.State);
    }

    public void ApplyState(CoordinatorState state)
    {
        _applyingState = true;
        try
        {
            _state = state;
            if (state.Profile is { } profile)
            {
                NicknameInput.Text = profile.Nickname;
                CharacterSelector.SelectedValue = PixelCharacterCatalog.NormalizeId(profile.CharacterId);
            }

            var selectedRoomId = (RoomList.SelectedItem as Room)?.Id ?? state.ActiveRoomId;
            RoomList.ItemsSource = state.Rooms;
            RoomList.SelectedItem = state.Rooms.FirstOrDefault(room => room.Id == selectedRoomId)
                ?? state.Rooms.FirstOrDefault(room => room.Id == state.ActiveRoomId);
            var active = ActiveRoom();
            MemberList.ItemsSource = active?.Members;
            ActiveRoomDetails.Text = active is null
                ? "아직 참여한 그룹이 없습니다."
                : active.InviteCodeReady
                    ? $"{active.Name} · {active.Members.Count}/12명"
                    : $"{active.Name} · {active.Members.Count}/12명 · 이전 초대 코드 폐기됨";
            CopyInviteButton.IsEnabled = active?.InviteCodeReady == true;
            RotateInviteButton.IsEnabled = active is not null
                && active.OwnerId == state.Profile?.Id
                && state.GroupOperation == GroupOperation.Idle;
            OwnerManagementCard.IsEnabled = active is not null
                && active.OwnerId == state.Profile?.Id
                && state.GroupOperation == GroupOperation.Idle;
            HistoryList.ItemsSource = state.ActiveRoomId is { } roomId
                ? state.Messages.Where(message => message.RoomId == roomId).ToArray()
                : Array.Empty<MessageLedgerEntry>();

            OverlayToggle.IsOn = state.Preferences.OverlayVisible;
            QuietModeToggle.IsOn = state.Preferences.QuietMode;
            ShowOfflineToggle.IsOn = state.Preferences.ShowOfflineMembers;
            StartupToggle.IsOn = state.Preferences.StartAtLogin;
            EdgeSelector.SelectedIndex = (int)state.Preferences.OverlayRegion.Edge;
            SpanSelector.SelectedIndex = (int)state.Preferences.OverlayRegion.Span;
            MonitorSelector.SelectedValue = state.Preferences.OverlayRegion.MonitorIdentifier
                ?? _coordinator.GetMonitors().FirstOrDefault(monitor => monitor.IsPrimary)?.Identifier;

#if DEBUG
            ValidationCard.Visibility = _coordinator.IsValidationMode
                ? Visibility.Visible
                : Visibility.Collapsed;
            ValidationPathText.Text = _coordinator.ValidationMetricsPath is { } path
                ? $"내보내기 경로: {path}"
                : "계측 renderer가 시작되지 않았습니다.";
            RefreshValidationMetrics();
#endif

            if (!string.IsNullOrWhiteSpace(state.ErrorMessage))
            {
                StatusInfoBar.Severity = InfoBarSeverity.Warning;
                StatusInfoBar.Message = state.ErrorMessage;
                StatusInfoBar.IsOpen = true;
            }
            else if (state.Connected)
            {
                StatusInfoBar.Severity = InfoBarSeverity.Success;
                StatusInfoBar.Message = "SIDEY 서버와 연결되었습니다.";
                StatusInfoBar.IsOpen = true;
            }
        }
        finally
        {
            _applyingState = false;
        }
    }

    public void ShowFatalError(Exception exception)
    {
        StatusInfoBar.Severity = InfoBarSeverity.Error;
        StatusInfoBar.Message = exception.Message;
        StatusInfoBar.IsOpen = true;
    }

    public void ShowPage(string tag)
    {
        var item = RootNavigation.MenuItems
            .OfType<NavigationViewItem>()
            .FirstOrDefault(candidate => StringComparer.Ordinal.Equals(candidate.Tag as string, tag));
        if (item is not null)
        {
            RootNavigation.SelectedItem = item;
        }
        AppWindow.Show();
        Activate();
    }

    public void CloseForExit()
    {
        _allowClose = true;
        Close();
    }

    public void CheckForUpdates() => _ = CheckForUpdatesAsync();

    private void OnAppWindowClosing(
        Microsoft.UI.Windowing.AppWindow sender,
        Microsoft.UI.Windowing.AppWindowClosingEventArgs args)
    {
        _ = sender;
        if (!_allowClose)
        {
            args.Cancel = true;
            AppWindow.Hide();
        }
    }

    private void OnNavigationSelectionChanged(
        NavigationView sender,
        NavigationViewSelectionChangedEventArgs args)
    {
        _ = sender;
        var tag = (args.SelectedItemContainer?.Tag as string) ?? "home";
        HomePage.Visibility = tag == "home" ? Visibility.Visible : Visibility.Collapsed;
        GroupsPage.Visibility = tag == "groups" ? Visibility.Visible : Visibility.Collapsed;
        HistoryPage.Visibility = tag == "history" ? Visibility.Visible : Visibility.Collapsed;
        SettingsPage.Visibility = tag == "settings" ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnOpenGroupsClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        RootNavigation.SelectedItem = RootNavigation.MenuItems[1];
    }

    private async void OnSaveProfileClicked(object sender, RoutedEventArgs args) =>
        await RunCommandAsync(
            () => _coordinator.SaveProfileAsync(
                NicknameInput.Text,
                CharacterSelector.SelectedValue as string ?? PixelCharacterCatalog.FallbackId),
            "프로필을 저장했습니다.");

    private async void OnCreateRoomClicked(object sender, RoutedEventArgs args) =>
        await RunCommandAsync(
            () => _coordinator.CreateRoomAsync(CreateRoomInput.Text),
            "그룹을 만들었습니다.");

    private async void OnJoinRoomClicked(object sender, RoutedEventArgs args) =>
        await RunCommandAsync(
            () => _coordinator.JoinRoomAsync(InviteCodeInput.Text),
            "그룹에 참여했습니다.");

    private async void OnRoomSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (_applyingState || RoomList.SelectedItem is not Room room || room.Id == _state.ActiveRoomId)
        {
            return;
        }

        await RunCommandAsync(() => _coordinator.SwitchRoomAsync(room.Id), "활성 그룹을 바꿨습니다.");
    }

    private async void OnCopyInviteClicked(object sender, RoutedEventArgs args)
    {
        var active = ActiveRoom();
        if (active is null)
        {
            return;
        }

        await RunCommandAsync(async () =>
        {
            if (!await _coordinator.CopyInviteCodeAsync(active.Id))
            {
                throw new InvalidOperationException("이 기기에 저장된 초대 코드가 없습니다.");
            }
        }, "초대 코드를 복사했습니다.");
    }

    private async void OnRotateInviteClicked(object sender, RoutedEventArgs args)
    {
        var active = ActiveRoom();
        if (active is null || active.OwnerId != _state.Profile?.Id)
        {
            ShowStatus("방장만 새 초대 코드를 발급할 수 있습니다.", InfoBarSeverity.Warning);
            return;
        }

        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = "새 초대 코드를 발급할까요?",
            Content = "기존 코드는 즉시 폐기되며 되돌릴 수 없습니다.",
            PrimaryButtonText = "새 코드 발급",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }

        await RunCommandAsync(
            () => _coordinator.RotateInviteCodeAsync(active.Id),
            "새 초대 코드를 발급해 이 기기의 Credential Manager에 저장했습니다.");
    }

    private void OnComposeClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _coordinator.RequestComposer();
    }

    private async void OnLeaveRoomClicked(object sender, RoutedEventArgs args)
    {
        var active = ActiveRoom();
        if (active is null)
        {
            return;
        }
        await RunCommandAsync(() => _coordinator.LeaveRoomAsync(active.Id), "그룹에서 나왔습니다.");
    }

    private async void OnRenameRoomClicked(object sender, RoutedEventArgs args)
    {
        var active = ActiveRoom();
        if (active is null)
        {
            return;
        }
        await RunCommandAsync(
            () => _coordinator.RenameRoomAsync(active.Id, RenameRoomInput.Text),
            "그룹 이름을 바꿨습니다.");
    }

    private async void OnRemoveMemberClicked(object sender, RoutedEventArgs args)
    {
        var active = ActiveRoom();
        if (active is null || MemberList.SelectedItem is not RoomMember member)
        {
            return;
        }
        if (member.UserId == active.OwnerId)
        {
            ShowStatus("방장은 자신을 추방할 수 없습니다.", InfoBarSeverity.Warning);
            return;
        }
        await RunCommandAsync(
            () => _coordinator.RemoveRoomMemberAsync(active.Id, member.UserId),
            "멤버를 그룹에서 내보냈습니다.");
    }

    private async void OnDeleteRoomClicked(object sender, RoutedEventArgs args)
    {
        var active = ActiveRoom();
        if (active is null)
        {
            return;
        }
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = "그룹을 삭제할까요?",
            Content = "멤버십과 메시지가 서버에서 함께 삭제되며 되돌릴 수 없습니다.",
            PrimaryButtonText = "삭제",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }
        await RunCommandAsync(() => _coordinator.DeleteRoomAsync(active.Id), "그룹을 삭제했습니다.");
    }

    private async void OnOverlayToggled(object sender, RoutedEventArgs args)
    {
        if (!_applyingState)
        {
            await RunCommandAsync(
                () => _coordinator.SetOverlayVisibleAsync(OverlayToggle.IsOn),
                null);
        }
    }

    private async void OnQuietModeToggled(object sender, RoutedEventArgs args)
    {
        if (!_applyingState)
        {
            await RunCommandAsync(
                () => _coordinator.SetQuietModeAsync(QuietModeToggle.IsOn),
                null);
        }
    }

    private async void OnShowOfflineToggled(object sender, RoutedEventArgs args)
    {
        if (!_applyingState)
        {
            await RunCommandAsync(
                () => _coordinator.SetShowOfflineMembersAsync(ShowOfflineToggle.IsOn),
                null);
        }
    }

    private async void OnStartupToggled(object sender, RoutedEventArgs args)
    {
        if (!_applyingState)
        {
            await RunCommandAsync(
                () => _coordinator.SetStartAtLoginAsync(StartupToggle.IsOn),
                null);
        }
    }

    private async void OnApplyRegionClicked(object sender, RoutedEventArgs args)
    {
        var edge = (OverlayEdge)Math.Clamp(EdgeSelector.SelectedIndex, 0, 3);
        var span = (OverlaySpan)Math.Clamp(SpanSelector.SelectedIndex, 0, 2);
        await RunCommandAsync(
            () => _coordinator.SetRegionAsync(new OverlayRegionPreference(
                edge,
                span,
                MonitorSelector.SelectedValue as string)),
            "오버레이 영역을 적용했습니다.");
    }

    private async void OnCheckUpdateClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        await CheckForUpdatesAsync();
    }

    private async Task CheckForUpdatesAsync()
    {
        UpdateButton.IsEnabled = false;
        try
        {
            var update = await _updates.CheckAsync();
            if (update is null)
            {
                ShowStatus("현재 버전이 최신입니다.", InfoBarSeverity.Success);
                return;
            }

            ShowStatus($"새 버전 {update.Version}이 있습니다. 공식 Release 페이지를 엽니다.", InfoBarSeverity.Informational);
            _updates.OpenOfficialReleasesPage();
        }
        catch (Exception exception)
        {
            ShowStatus($"업데이트 확인 실패: {exception.Message}", InfoBarSeverity.Error);
        }
        finally
        {
            UpdateButton.IsEnabled = true;
        }
    }

    private async void OnExportValidationMetricsClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        try
        {
            var path = await _coordinator.ExportValidationMetricsAsync();
            if (path is null)
            {
                ShowStatus("계측 renderer가 실행 중이 아닙니다.", InfoBarSeverity.Warning);
                return;
            }

            ValidationPathText.Text = $"내보내기 경로: {path}";
            ShowStatus("현재 계측 JSON을 내보냈습니다. 수동 결과는 not_run 상태입니다.", InfoBarSeverity.Success);
        }
        catch (Exception exception)
        {
            ShowStatus($"계측 내보내기 실패: {exception.Message}", InfoBarSeverity.Error);
        }
    }

    private async Task RunCommandAsync(Func<Task> action, string? successMessage)
    {
        try
        {
            await action();
            if (!string.IsNullOrWhiteSpace(successMessage))
            {
                ShowStatus(successMessage, InfoBarSeverity.Success);
            }
        }
        catch (Exception exception)
        {
            ShowStatus(exception.Message, InfoBarSeverity.Error);
        }
    }

    private Room? ActiveRoom() => _state.ActiveRoomId is { } roomId
        ? _state.Rooms.FirstOrDefault(room => room.Id == roomId)
        : null;

    private void ShowStatus(string message, InfoBarSeverity severity)
    {
        StatusInfoBar.Message = message;
        StatusInfoBar.Severity = severity;
        StatusInfoBar.IsOpen = true;
    }

#if DEBUG
    private void RefreshValidationMetrics()
    {
        var summary = _coordinator.ValidationMetricsSummary;
        ValidationMetricsText.Text = summary is null
            ? "계측 sample 없음"
            : $"경과 {summary.ElapsedSeconds:F0}s · sample {summary.SampleCount} · "
                + $"최대 frame {summary.MaximumFrameMilliseconds:F2}ms · "
                + $"working set {summary.CurrentWorkingSetBytes / 1_048_576d:F1}MB "
                + $"(peak {summary.PeakWorkingSetBytes / 1_048_576d:F1}MB) · "
                + $"GDI {summary.MaximumGdiHandles} · USER {summary.MaximumUserHandles}";
    }
#endif
}
