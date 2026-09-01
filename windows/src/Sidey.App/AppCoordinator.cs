using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Core.Realtime;
using Sidey.Infrastructure;
using Sidey.Overlay;
using Sidey.Platform.Windows;
using System.Diagnostics;
using Windows.ApplicationModel.DataTransfer;

namespace Sidey.App;

public enum GroupOperation
{
    Idle,
    Creating,
    Joining,
    Switching,
}

public sealed record CoordinatorState(
    Profile? Profile,
    IReadOnlyList<Room> Rooms,
    Guid? ActiveRoomId,
    IReadOnlyList<MessageLedgerEntry> Messages,
    AppPreferences Preferences,
    bool Connected,
    GroupOperation GroupOperation,
    string? ErrorMessage)
{
    public static CoordinatorState Initial { get; } = new(
        null,
        Array.Empty<Room>(),
        null,
        Array.Empty<MessageLedgerEntry>(),
        AppPreferences.Default,
        false,
        GroupOperation.Idle,
        null);
}

/// <summary>
/// Owns application lifetime, server mutations, room switching and the native
/// overlay. Feature windows consume only CoordinatorState and commands.
/// </summary>
public sealed class AppCoordinator : IAsyncDisposable
{
    private readonly IPreferencesStore _preferencesStore;
    private readonly ICredentialStore _credentialStore;
    private readonly CancellationTokenSource _lifetime = new();
    private readonly WindowsStartupService _startup = new();
    private readonly IActivityMonitor _activityMonitor = new WindowsActivityMonitor();
    private readonly MessageLedger _messages = new();
    private readonly ActiveBubbleLedger _bubbles = new();
    private readonly CharacterPulseCooldown _pulseCooldown = new();
    private readonly TypingLease _typingLease = new();
    private readonly List<CharacterPulseEvent> _pulses = [];
    private readonly HashSet<(Guid RoomId, Guid UserId)> _typing = [];
    private readonly Dictionary<Guid, int> _unreadByRoom = [];
    private IAuthService? _auth;
    private IBackendGateway? _backend;
    private NativePixelWorldSession? _overlay;
    private RoomSwitchPipeline? _roomSwitch;
    private Task? _eventPump;
    private Task? _activityPump;
    private CoordinatorState _state = CoordinatorState.Initial;
    private bool _validationMode = false;
    private Guid? _previewRoomId;
    private Guid? _previewUserId;
    private WorldSnapshot? _previewSnapshot;
    private CancellationTokenSource? _typingKeepalive;

    public AppCoordinator(
        IPreferencesStore? preferencesStore = null,
        ICredentialStore? credentialStore = null)
    {
        _preferencesStore = preferencesStore ?? new AtomicPreferencesStore();
        _credentialStore = credentialStore ?? new WindowsCredentialStore();
    }

    public CoordinatorState State => _state;

    public bool IsValidationMode => _validationMode;

    public string? ValidationMetricsPath => _overlay?.ValidationMetricsPath;

    public ValidationMetricsSummary? ValidationMetricsSummary => _overlay?.ValidationMetricsSummary;

    public int UnreadCount(Guid roomId) => _unreadByRoom.GetValueOrDefault(roomId);

    public int TotalUnreadCount => _unreadByRoom.Values.Sum();

    public event Action<CoordinatorState>? StateChanged;
    public event Action? ComposerRequested;
    public event Action? PulseRequested;
    public event Action<string>? SendFailed;
    public event Action<Exception>? RenderingFailed;
    public event Action? GroupSetupRequested;

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        var preferences = await _preferencesStore.LoadAsync(cancellationToken);
        preferences = preferences with { StartAtLogin = _startup.IsEnabled() };
        _state = _state with { Preferences = preferences };

#if DEBUG
        _validationMode = string.Equals(
            Environment.GetEnvironmentVariable("SIDEY_WINDOWS_VALIDATION_MODE"),
            "1",
            StringComparison.Ordinal);
#endif

        SupabaseRuntimeConfiguration? configuration;
#if DEBUG
        configuration = _validationMode ? null : SupabaseRuntimeConfiguration.FromEnvironment();
#else
        configuration = SupabaseRuntimeConfiguration.FromEnvironment();
#endif
        if (configuration is null)
        {
#if DEBUG
            StartPreviewOverlay(preferences);
            SetState(_state with
            {
                ErrorMessage = _validationMode
                    ? "내부 햄스터 제한 renderer 계측 모드입니다. 수동 검증 결과는 아직 기록되지 않았습니다."
                    : "백엔드 환경변수가 없어 5캐릭터 로컬 미리보기로 실행 중입니다.",
            });
#else
            SetState(_state with
            {
                ErrorMessage = "SIDEY 서버 구성이 없습니다. 배포 구성을 확인해 주세요.",
            });
#endif
            return;
        }

        var auth = new SupabaseAnonymousAuthService(configuration, _credentialStore);
        var stored = await _credentialStore.ReadAsync(
            CredentialKey.SupabaseSession,
            cancellationToken);
        await AnonymousSessionBootstrapper.RestoreOrCreateAsync(
            auth,
            hasStoredSession: !string.IsNullOrWhiteSpace(stored),
            cancellationToken);
        var backend = new SupabaseBackendGateway(configuration, auth, _credentialStore);
        _auth = auth;
        _backend = backend;

        var snapshot = await backend.FetchSnapshotAsync(cancellationToken);
        ApplySnapshot(snapshot);
        var activeRoomId = SelectActiveRoom(preferences.ActiveRoomId, snapshot.Rooms);
        _state = _state with { ActiveRoomId = activeRoomId, Connected = true, ErrorMessage = null };
        if (activeRoomId is { } roomId)
        {
            var history = await backend.FetchRecentMessagesAsync(roomId, cancellationToken);
            _messages.ReplaceConfirmed(roomId, history);
            StartOverlay(CurrentWorldSnapshot());
        }

        _roomSwitch = new RoomSwitchPipeline(
            PerformRoomSwitchAsync,
            RestoreCommittedRoomAsync,
            CommitRoomSwitch);
        _roomSwitch.InitializeCommittedRoom(activeRoomId);
        await backend.SynchronizeRealtimeRoomsAsync(
            RoomEpochs(snapshot.Rooms),
            activeRoomId,
            PresenceState.Online,
            cancellationToken);
        _eventPump = PumpBackendEventsAsync();
        _activityPump = PumpActivityAsync();
        await PersistPreferencesAsync(cancellationToken);
        PublishState();
    }

    public async Task SaveProfileAsync(
        string nickname,
        string characterId,
        CancellationToken cancellationToken = default)
    {
        var backend = RequiredBackend();
        var profile = await backend.SaveProfileAsync(nickname, characterId, cancellationToken);
        SetState(_state with
        {
            Profile = profile,
            Preferences = _state.Preferences with { OnboardingCompleted = true },
            ErrorMessage = null,
        });
        await PersistPreferencesAsync(cancellationToken);
        ApplyWorldSnapshot();
    }

    public async Task CreateRoomAsync(string name, CancellationToken cancellationToken = default)
    {
        EnsureMutationsAvailable();
        SetState(_state with { GroupOperation = GroupOperation.Creating, ErrorMessage = null });
        try
        {
            var result = await RequiredBackend().CreateRoomAsync(name, cancellationToken);
            await RefreshSnapshotAndSelectAsync(result.Room.Id, cancellationToken);
        }
        catch (Exception exception)
        {
            SetState(_state with { ErrorMessage = exception.Message });
            throw;
        }
        finally
        {
            SetState(_state with { GroupOperation = GroupOperation.Idle });
        }
    }

    public async Task JoinRoomAsync(string inviteCode, CancellationToken cancellationToken = default)
    {
        EnsureMutationsAvailable();
        SetState(_state with { GroupOperation = GroupOperation.Joining, ErrorMessage = null });
        try
        {
            var room = await RequiredBackend().JoinRoomAsync(inviteCode, cancellationToken);
            await RefreshSnapshotAndSelectAsync(room.Id, cancellationToken);
        }
        catch (Exception exception)
        {
            SetState(_state with { ErrorMessage = exception.Message });
            throw;
        }
        finally
        {
            SetState(_state with { GroupOperation = GroupOperation.Idle });
        }
    }

    public async Task SwitchRoomAsync(Guid roomId, CancellationToken cancellationToken = default)
    {
        if (_roomSwitch is null
            || _state.ActiveRoomId == roomId
            || _state.Rooms.All(room => room.Id != roomId))
        {
            return;
        }

        SetState(_state with { GroupOperation = GroupOperation.Switching, ErrorMessage = null });
        try
        {
            await _roomSwitch.RequestAsync(roomId, cancellationToken);
        }
        catch (Exception exception)
        {
            SetState(_state with { ErrorMessage = exception.Message });
            throw;
        }
        finally
        {
            SetState(_state with { GroupOperation = GroupOperation.Idle });
        }
    }

    public async Task RenameRoomAsync(
        Guid roomId,
        string name,
        CancellationToken cancellationToken = default)
    {
        EnsureMutationsAvailable();
        await RequiredBackend().RenameRoomAsync(roomId, name, cancellationToken);
        await RefreshSnapshotAsync(cancellationToken);
    }

    public async Task RotateInviteCodeAsync(
        Guid roomId,
        CancellationToken cancellationToken = default)
    {
        EnsureMutationsAvailable();
        await RequiredBackend().RotateInviteCodeAsync(roomId, cancellationToken);
        await RefreshSnapshotAsync(cancellationToken);
    }

    public async Task RemoveRoomMemberAsync(
        Guid roomId,
        Guid userId,
        CancellationToken cancellationToken = default)
    {
        EnsureMutationsAvailable();
        await RequiredBackend().RemoveRoomMemberAsync(roomId, userId, cancellationToken);
        await RefreshSnapshotAsync(cancellationToken);
    }

    public async Task DeleteRoomAsync(Guid roomId, CancellationToken cancellationToken = default)
    {
        EnsureMutationsAvailable();
        await RequiredBackend().DeleteRoomAsync(roomId, cancellationToken);
        await RefreshSnapshotAsync(cancellationToken);
    }

    public async Task LeaveRoomAsync(Guid roomId, CancellationToken cancellationToken = default)
    {
        EnsureMutationsAvailable();
        await RequiredBackend().LeaveRoomAsync(roomId, cancellationToken);
        await RefreshSnapshotAsync(cancellationToken);
    }

    public ValueTask<string?> GetInviteCodeAsync(
        Guid roomId,
        CancellationToken cancellationToken = default) =>
        _credentialStore.ReadInviteCodeAsync(roomId, cancellationToken);

    public async Task<bool> CopyInviteCodeAsync(
        Guid roomId,
        CancellationToken cancellationToken = default)
    {
        var room = _state.Rooms.FirstOrDefault(room => room.Id == roomId);
        if (room is null)
        {
            throw new InvalidOperationException("그룹을 찾을 수 없습니다.");
        }
        if (!room.InviteCodeReady)
        {
            throw new InvalidOperationException(
                "이 그룹의 이전 초대 코드는 폐기됐습니다. 방장이 새 코드를 발급해야 합니다.");
        }

        var code = await GetInviteCodeAsync(roomId, cancellationToken);
        if (string.IsNullOrWhiteSpace(code))
        {
            return false;
        }
        var normalizedCode = code.Replace("-", string.Empty, StringComparison.Ordinal)
            .Trim()
            .ToUpperInvariant();
        var hintSuffix = room.InviteCodeHint[(room.InviteCodeHint.LastIndexOf('-') + 1)..]
            .ToUpperInvariant();
        if (hintSuffix.Length != 4
            || normalizedCode.Length < hintSuffix.Length
            || !normalizedCode.EndsWith(hintSuffix, StringComparison.Ordinal))
        {
            await _credentialStore.DeleteInviteCodeAsync(roomId, cancellationToken);
            throw new InvalidOperationException(
                "이 기기에 저장된 초대 코드는 이미 교체됐습니다. 방장에게 새 코드를 받아 주세요.");
        }

        var data = new DataPackage();
        data.SetText(code);
        Clipboard.SetContent(data);
        Clipboard.Flush();
        return true;
    }

    public async Task SendMessageAsync(string body, CancellationToken cancellationToken = default)
    {
        if (_state.ActiveRoomId is not { } roomId || _state.Profile is not { } profile)
        {
            throw new InvalidOperationException("활성 그룹과 프로필이 필요합니다.");
        }

        var normalized = MessageValidator.Normalize(body);
        if (!MessageValidator.IsValid(normalized))
        {
            throw new ArgumentException("메시지는 1~200자, 최대 3줄이어야 합니다.", nameof(body));
        }

        var id = Guid.NewGuid();
        _messages.Stage(id, roomId, profile.Id, normalized);
        _bubbles.Show(profile.Id, id, normalized);
        PublishState();
        ApplyWorldSnapshot();
        try
        {
            var confirmed = await RequiredBackend().SendMessageAsync(
                id,
                roomId,
                normalized,
                cancellationToken);
            _messages.Confirm(confirmed);
            PublishState();
        }
        catch
        {
            _bubbles.Remove(id);
            var restored = _messages.Fail(id);
            PublishState();
            ApplyWorldSnapshot();
            if (restored is not null)
            {
                SendFailed?.Invoke(restored);
            }
            throw;
        }
    }

    public async Task SetOverlayVisibleAsync(bool visible, CancellationToken cancellationToken = default)
    {
        if (_overlay is not null)
        {
            await _overlay.SetVisibleAsync(visible, cancellationToken);
        }
        SetState(_state with
        {
            Preferences = _state.Preferences with { OverlayVisible = visible },
        });
        await PersistPreferencesAsync(cancellationToken);
    }

    public async Task SetQuietModeAsync(bool enabled, CancellationToken cancellationToken = default)
    {
        SetState(_state with
        {
            Preferences = _state.Preferences with { QuietMode = enabled },
        });
        await PersistPreferencesAsync(cancellationToken);
        ApplyWorldSnapshot();
    }

    public async Task SetShowOfflineMembersAsync(
        bool enabled,
        CancellationToken cancellationToken = default)
    {
        SetState(_state with
        {
            Preferences = _state.Preferences with { ShowOfflineMembers = enabled },
        });
        await PersistPreferencesAsync(cancellationToken);
        ApplyWorldSnapshot();
    }

    public async Task SetStartAtLoginAsync(
        bool enabled,
        CancellationToken cancellationToken = default)
    {
        _startup.SetEnabled(enabled);
        SetState(_state with
        {
            Preferences = _state.Preferences with { StartAtLogin = enabled },
        });
        await PersistPreferencesAsync(cancellationToken);
    }

    public IReadOnlyList<WindowsMonitorInfo> GetMonitors() => WindowsMonitorService.GetAll();

    public async Task SetTypingAsync(bool active, CancellationToken cancellationToken = default)
    {
        if (_backend is null)
        {
            return;
        }

        var actions = _typingLease.Update(active, _state.ActiveRoomId);
        foreach (var action in actions)
        {
            switch (action)
            {
                case TypingLeaseAction.Start start:
                    try
                    {
                        await _backend.BroadcastTypingAsync(
                            start.RoomId,
                            active: true,
                            keepalive: false,
                            cancellationToken);
                        StartTypingKeepalive(start.RoomId);
                    }
                    catch
                    {
                        _typingLease.Update(active: false, requestedRoomId: null);
                        StopTypingKeepalive();
                        throw;
                    }
                    break;
                case TypingLeaseAction.Stop stop:
                    StopTypingKeepalive();
                    await _backend.BroadcastTypingAsync(
                        stop.RoomId,
                        active: false,
                        keepalive: false,
                        cancellationToken);
                    break;
            }
        }
    }

    public async Task SetRegionAsync(
        OverlayRegionPreference preference,
        CancellationToken cancellationToken = default)
    {
        SetState(_state with
        {
            Preferences = _state.Preferences with { OverlayRegion = preference },
        });
        await PersistPreferencesAsync(cancellationToken);
        if (_overlay is not null)
        {
            if (_backend is null && _previewSnapshot is not null)
            {
                StartPreviewOverlay(_state.Preferences);
            }
            else
            {
                _overlay.Dispose();
                _overlay = null;
                StartOverlay(CurrentWorldSnapshot());
            }
        }
    }

    public void RequestComposer() => ComposerRequested?.Invoke();

    public void RequestCharacterPulse() => PulseRequested?.Invoke();

    public async Task PulseCurrentCharacterAsync(CancellationToken cancellationToken = default)
    {
        var roomId = _state.ActiveRoomId ?? _previewRoomId;
        var userId = _state.Profile?.Id ?? _previewUserId;
        if (roomId is null || userId is null)
        {
            return;
        }

        var uptime = TimeSpan.FromSeconds(
            Stopwatch.GetTimestamp() / (double)Stopwatch.Frequency);
        if (!_pulseCooldown.Accept(roomId.Value, userId.Value, uptime))
        {
            return;
        }

        var pulse = new CharacterPulseEvent(Guid.NewGuid(), roomId.Value, userId.Value);
        _pulses.Add(pulse);
        if (_pulses.Count > 64)
        {
            _pulses.RemoveRange(0, _pulses.Count - 64);
        }
        ApplyWorldSnapshot();

        if (_backend is not null)
        {
            await _backend.BroadcastCharacterPulseAsync(
                roomId.Value,
                pulse.Id,
                cancellationToken);
        }
    }

    public Task<string?> ExportValidationMetricsAsync(
        CancellationToken cancellationToken = default) =>
        _overlay?.ExportValidationMetricsAsync(cancellationToken)
        ?? Task.FromResult<string?>(null);

    public async ValueTask DisposeAsync()
    {
        _lifetime.Cancel();
        StopTypingKeepalive();
        if (_eventPump is not null)
        {
            try
            {
                await _eventPump.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }
        }
        if (_activityPump is not null)
        {
            try
            {
                await _activityPump.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }
        }
        if (_roomSwitch is not null)
        {
            await _roomSwitch.DisposeAsync().ConfigureAwait(false);
        }
        if (_backend is SupabaseBackendGateway supabase)
        {
            await supabase.DisposeAsync().ConfigureAwait(false);
        }
        if (_auth is IDisposable disposableAuth)
        {
            disposableAuth.Dispose();
        }
        _overlay?.Dispose();
        await _activityMonitor.DisposeAsync().ConfigureAwait(false);
        _lifetime.Dispose();
    }

    private async Task<IReadOnlyList<ChatMessage>> PerformRoomSwitchAsync(
        Guid roomId,
        CancellationToken cancellationToken)
    {
        var backend = RequiredBackend();
        await backend.SynchronizeRealtimeRoomsAsync(
            RoomEpochs(_state.Rooms),
            roomId,
            PresenceState.Online,
            cancellationToken);
        return await backend.FetchRecentMessagesAsync(roomId, cancellationToken);
    }

    private Task RestoreCommittedRoomAsync(Guid? roomId, CancellationToken cancellationToken) =>
        RequiredBackend().SynchronizeRealtimeRoomsAsync(
            RoomEpochs(_state.Rooms),
            roomId,
            PresenceState.Online,
            cancellationToken);

    private void CommitRoomSwitch(Guid roomId, IReadOnlyList<ChatMessage> history)
    {
        _messages.ReplaceConfirmed(roomId, history);
        _bubbles.Clear();
        _unreadByRoom[roomId] = 0;
        _state = _state with
        {
            ActiveRoomId = roomId,
            Preferences = _state.Preferences with { ActiveRoomId = roomId },
        };
        _ = PersistCommittedRoomAsync();
        PublishState();
        if (_overlay is null)
        {
            StartOverlay(CurrentWorldSnapshot());
        }
        else
        {
            ApplyWorldSnapshot();
        }
    }

    private async Task PumpBackendEventsAsync()
    {
        try
        {
            await foreach (var backendEvent in RequiredBackend().SubscribeAsync(_lifetime.Token))
            {
                switch (backendEvent)
                {
                    case BackendEvent.SnapshotReceived snapshot:
                        await ReconcileSnapshotAsync(snapshot.Snapshot, _lifetime.Token);
                        break;
                    case BackendEvent.MessageReceived message:
                        _messages.Confirm(message.Message);
                        _bubbles.Show(
                            message.Message.SenderId,
                            message.Message.Id,
                            message.Message.Body);
                        if (message.Message.RoomId != _state.ActiveRoomId
                            && message.Message.SenderId != _state.Profile?.Id)
                        {
                            _unreadByRoom[message.Message.RoomId] = Math.Min(
                                99,
                                _unreadByRoom.GetValueOrDefault(message.Message.RoomId) + 1);
                        }
                        PublishState();
                        ApplyWorldSnapshot();
                        break;
                    case BackendEvent.MessageDeleted deleted:
                        _messages.Remove(deleted.RoomId, deleted.MessageId);
                        _bubbles.Remove(deleted.MessageId);
                        PublishState();
                        ApplyWorldSnapshot();
                        break;
                    case BackendEvent.MessagesReplaced replaced:
                        _messages.ReplaceConfirmed(replaced.RoomId, replaced.Messages);
                        if (replaced.RoomId == _state.ActiveRoomId)
                        {
                            _bubbles.Clear();
                        }
                        PublishState();
                        ApplyWorldSnapshot();
                        break;
                    case BackendEvent.PresenceChanged presence:
                        UpdateMember(presence.RoomId, presence.UserId, member => member with
                        {
                            Presence = presence.State,
                        });
                        break;
                    case BackendEvent.TypingChanged typing:
                        if (typing.Active)
                        {
                            _typing.Add((typing.RoomId, typing.UserId));
                        }
                        else
                        {
                            _typing.Remove((typing.RoomId, typing.UserId));
                        }
                        ApplyWorldSnapshot();
                        break;
                    case BackendEvent.CharacterPulsed pulsed:
                        if (_pulseCooldown.Accept(
                            pulsed.Pulse.RoomId,
                            pulsed.Pulse.UserId,
                            TimeSpan.FromSeconds(
                                Stopwatch.GetTimestamp() / (double)Stopwatch.Frequency)))
                        {
                            _pulses.Add(pulsed.Pulse);
                            if (_pulses.Count > 64)
                            {
                                _pulses.RemoveRange(0, _pulses.Count - 64);
                            }
                            ApplyWorldSnapshot();
                        }
                        break;
                    case BackendEvent.ConnectionChanged connection:
                        SetState(_state with { Connected = connection.Connected });
                        break;
                    case BackendEvent.TechnicalError error:
                        SetState(_state with { ErrorMessage = error.Message });
                        break;
                }
            }
        }
        catch (OperationCanceledException) when (_lifetime.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            SetState(_state with { Connected = false, ErrorMessage = exception.Message });
        }
    }

    private async Task PumpActivityAsync()
    {
        await foreach (var presence in _activityMonitor.ObserveAsync(_lifetime.Token))
        {
            if (_backend is null || _state.ActiveRoomId is not { } roomId)
            {
                continue;
            }
            try
            {
                await _backend.PublishPresenceAsync(roomId, presence, _lifetime.Token);
            }
            catch when (!_lifetime.IsCancellationRequested)
            {
                SetState(_state with { Connected = false });
            }
        }
    }

    private void UpdateMember(
        Guid roomId,
        Guid userId,
        Func<RoomMember, RoomMember> update)
    {
        _state = _state with
        {
            Rooms = _state.Rooms.Select(room => room.Id == roomId
                ? room with
                {
                    Members = room.Members.Select(member => member.UserId == userId
                        ? update(member)
                        : member).ToArray(),
                }
                : room).ToArray(),
        };
        PublishState();
        ApplyWorldSnapshot();
    }

    private void ApplySnapshot(BackendSnapshot snapshot)
    {
        var activeRoomId = SelectActiveRoom(_state.ActiveRoomId, snapshot.Rooms);
        var roomIds = snapshot.Rooms.Select(room => room.Id).ToHashSet();
        foreach (var removedRoomId in _unreadByRoom.Keys.Where(id => !roomIds.Contains(id)).ToArray())
        {
            _unreadByRoom.Remove(removedRoomId);
        }
        _state = _state with
        {
            Profile = snapshot.Profile,
            Rooms = snapshot.Rooms,
            ActiveRoomId = activeRoomId,
            Preferences = _state.Preferences with { ActiveRoomId = activeRoomId },
        };
        PublishState();
    }

    private async Task RefreshSnapshotAsync(CancellationToken cancellationToken)
    {
        var snapshot = await RequiredBackend().FetchSnapshotAsync(cancellationToken);
        await ReconcileSnapshotAsync(snapshot, cancellationToken);
    }

    private async Task ReconcileSnapshotAsync(
        BackendSnapshot snapshot,
        CancellationToken cancellationToken)
    {
        var previousActiveRoomId = _state.ActiveRoomId;
        ApplySnapshot(snapshot);
        await RequiredBackend().SynchronizeRealtimeRoomsAsync(
            RoomEpochs(snapshot.Rooms),
            _state.ActiveRoomId,
            PresenceState.Online,
            cancellationToken);
        if (_state.ActiveRoomId != previousActiveRoomId)
        {
            StopTypingKeepalive();
            _typingLease.Update(active: false, requestedRoomId: null);
            _typing.Clear();
            _bubbles.Clear();
            _roomSwitch?.InitializeCommittedRoom(_state.ActiveRoomId);
            if (_state.ActiveRoomId is { } activeRoomId)
            {
                var history = await RequiredBackend().FetchRecentMessagesAsync(
                    activeRoomId,
                    cancellationToken);
                _messages.ReplaceConfirmed(activeRoomId, history);
                _unreadByRoom[activeRoomId] = 0;
                if (_overlay is null)
                {
                    StartOverlay(CurrentWorldSnapshot());
                }
            }
            else
            {
                _overlay?.Dispose();
                _overlay = null;
                if (previousActiveRoomId is not null)
                {
                    GroupSetupRequested?.Invoke();
                }
            }
        }
        await PersistPreferencesAsync(cancellationToken);
        PublishState();
        ApplyWorldSnapshot();
    }

    private async Task RefreshSnapshotAndSelectAsync(Guid roomId, CancellationToken cancellationToken)
    {
        await RefreshSnapshotAsync(cancellationToken);
        await SwitchRoomAsync(roomId, cancellationToken);
    }

    private void StartPreviewOverlay(AppPreferences preferences)
    {
        var ids = _validationMode
            ? new[] { PixelCharacterCatalog.FallbackId }
            : PixelCharacterCatalog.All.Select(character => character.Id).ToArray();
        var snapshot = PixelWorldPreview.Create(
            ids,
            preferences.InstallationSeed,
            preferences.OverlayRegion.Edge);
        _previewRoomId = snapshot.RoomId;
        _previewUserId = snapshot.Members.FirstOrDefault(member => member.IsCurrentUser)?.Id;
        _previewSnapshot = snapshot;
        StartOverlay(snapshot, _validationMode ? ids.ToHashSet(StringComparer.Ordinal) : null);
    }

    private void StartOverlay(WorldSnapshot snapshot, IReadOnlySet<string>? validationIds = null)
    {
        _overlay?.Dispose();
        _overlay = NativePixelWorldSession.Start(
            _state.Preferences.OverlayRegion,
            snapshot,
            RequestComposer,
            RequestCharacterPulse,
            exception => RenderingFailed?.Invoke(exception),
            new NativePixelWorldSessionOptions(
                ValidationCharacterIds: validationIds,
                CollectValidationMetrics: validationIds is not null));
    }

    private void ApplyWorldSnapshot()
    {
        if (_overlay is null)
        {
            return;
        }
        _bubbles.Prune();
        _overlay.ApplyAsync(CurrentWorldSnapshot()).GetAwaiter().GetResult();
    }

    private WorldSnapshot CurrentWorldSnapshot()
    {
        if (_backend is null && _previewSnapshot is { } preview)
        {
            return preview with
            {
                Pulses = _pulses.ToArray(),
                Edge = _state.Preferences.OverlayRegion.Edge,
                InstallationSeed = _state.Preferences.InstallationSeed,
            };
        }

        var room = _state.ActiveRoomId is { } roomId
            ? _state.Rooms.FirstOrDefault(candidate => candidate.Id == roomId)
            : null;
        var members = room?.Members
            .Where(member => _state.Preferences.ShowOfflineMembers
                || member.Presence != PresenceState.Offline)
            .Select(member => new PixelWorldMember(
                member.UserId,
                member.Nickname,
                PixelCharacterCatalog.NormalizeId(member.CharacterId),
                member.Presence,
                IsTyping: room is not null && _typing.Contains((room.Id, member.UserId)),
                IsCurrentUser: member.UserId == _state.Profile?.Id))
            .ToArray() ?? [];
        return new WorldSnapshot(
            room?.Id,
            members,
            _state.Preferences.QuietMode ? [] : _bubbles.Bubbles.ToArray(),
            _pulses.ToArray(),
            _state.Preferences.OverlayRegion.Edge,
            _state.Preferences.InstallationSeed);
    }

    private async Task PersistPreferencesAsync(CancellationToken cancellationToken) =>
        await _preferencesStore.SaveAsync(_state.Preferences, cancellationToken).ConfigureAwait(false);

    private IBackendGateway RequiredBackend() =>
        _backend ?? throw new InvalidOperationException("SIDEY 서버 연결이 구성되지 않았습니다.");

    private void EnsureMutationsAvailable()
    {
        if (_state.GroupOperation != GroupOperation.Idle)
        {
            throw new InvalidOperationException("다른 그룹 작업이 끝난 뒤 다시 시도해 주세요.");
        }
    }

    private void SetState(CoordinatorState state)
    {
        _state = state with { Messages = _messages.Entries.ToArray() };
        StateChanged?.Invoke(_state);
    }

    private void PublishState() => SetState(_state);

    private void StartTypingKeepalive(Guid roomId)
    {
        StopTypingKeepalive();
        _typingKeepalive = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
        _ = RunTypingKeepaliveAsync(roomId, _typingKeepalive.Token);
    }

    private async Task RunTypingKeepaliveAsync(Guid roomId, CancellationToken cancellationToken)
    {
        try
        {
            using var timer = new PeriodicTimer(TypingLease.KeepaliveInterval);
            while (await timer.WaitForNextTickAsync(cancellationToken).ConfigureAwait(false))
            {
                if (_typingLease.RoomId != roomId || _backend is null)
                {
                    return;
                }

                await _backend.BroadcastTypingAsync(
                    roomId,
                    active: true,
                    keepalive: true,
                    cancellationToken).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception exception)
        {
            _typingLease.Update(active: false, requestedRoomId: null);
            SetState(_state with
            {
                Connected = false,
                ErrorMessage = $"typing 상태 갱신 실패: {exception.Message}",
            });
        }
    }

    private async Task PersistCommittedRoomAsync()
    {
        try
        {
            await PersistPreferencesAsync(_lifetime.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (_lifetime.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            SetState(_state with { ErrorMessage = $"설정 저장 실패: {exception.Message}" });
        }
    }

    private void StopTypingKeepalive()
    {
        _typingKeepalive?.Cancel();
        _typingKeepalive?.Dispose();
        _typingKeepalive = null;
    }

    private static Guid? SelectActiveRoom(Guid? requested, IReadOnlyList<Room> rooms) =>
        requested is { } roomId && rooms.Any(room => room.Id == roomId)
            ? roomId
            : rooms.FirstOrDefault()?.Id;

    private static IReadOnlyDictionary<Guid, long> RoomEpochs(IReadOnlyList<Room> rooms) =>
        rooms.ToDictionary(room => room.Id, room => room.RealtimeEpoch);
}
