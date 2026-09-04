using System.Diagnostics;
using System.Globalization;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Sidey.Core.Realtime;
using Sidey.Infrastructure;
using Sidey.Overlay;
using Sidey.Platform.Windows;
using Sidey.Presentation.Services;
using Windows.ApplicationModel.DataTransfer;

namespace Sidey.App;

/// <summary>
/// Owns application lifetime, server mutations, room switching and the native
/// overlay. Feature windows consume only CoordinatorState and commands.
/// </summary>
public sealed class AppCoordinator : ISideyCoordinator, IAsyncDisposable
{
    private readonly IPreferencesStore _preferencesStore;
    private readonly ICredentialStore _credentialStore;
    private readonly CancellationTokenSource _lifetime = new();
    private readonly WindowsStartupService _startup = new();
    private readonly IActivityMonitor _activityMonitor = new WindowsActivityMonitor();
    private readonly MessageLedger _messages = new();
    private readonly ActiveBubbleLedger _bubbles = new();
    private readonly CharacterPulseCooldown _pulseCooldown = new();
    private readonly CharacterThrowCooldown _throwCooldown = new();
    private readonly TypingLease _typingLease = new();
    private readonly List<CharacterPulseEvent> _pendingPulses = [];
    private readonly List<CharacterThrowEvent> _pendingThrows = [];
    private readonly HashSet<(Guid RoomId, Guid UserId)> _typing = [];
    private readonly Dictionary<(Guid RoomId, Guid UserId), PresenceState> _basePresence = [];
    private readonly Dictionary<Guid, int> _unreadByRoom = [];
    private IAuthService? _auth;
    private IBackendGateway? _backend;
    private NativePixelWorldSession? _overlay;
    private RoomSwitchPipeline? _roomSwitch;
    private Task? _eventPump;
    private Task? _activityPump;
    private long _groupOperationGeneration;
    private CoordinatorState _state = CoordinatorState.Initial;
    private bool _validationMode = false;
    private Guid? _previewRoomId;
    private Guid? _previewUserId;
    private WorldSnapshot? _previewSnapshot;
    private CancellationTokenSource? _typingKeepalive;
    private PresenceState _localPresence = PresenceState.Online;
    private bool _cachedStateLoaded;

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

    public ValidationMetricsSnapshot? ValidationMetricsSummary
    {
        get
        {
            ValidationMetricsSummary? summary = _overlay?.ValidationMetricsSummary;
            return summary is null
                ? null
                : new ValidationMetricsSnapshot(
                    summary.ElapsedSeconds,
                    summary.SampleCount,
                    summary.MaximumFrameMilliseconds,
                    summary.CurrentWorkingSetBytes,
                    summary.PeakWorkingSetBytes,
                    summary.MaximumGdiHandles,
                    summary.MaximumUserHandles);
        }
    }

    public int UnreadCount(Guid roomId) => _unreadByRoom.GetValueOrDefault(roomId);

    public int TotalUnreadCount => _unreadByRoom.Values.Sum();

    public Task<MessageHistoryPage> FetchMessagePageAsync(
        Guid roomId,
        MessageHistoryCursor? before,
        int limit = 50,
        CancellationToken cancellationToken = default) =>
        RequiredBackend().FetchMessagePageAsync(roomId, before, limit, cancellationToken);

    public event Action<CoordinatorState>? StateChanged;
    public event Action? ComposerRequested;
    public event Action? PulseRequested;
    public event Action<Guid>? CharacterThrowRequested;
    public event Action<string, Exception>? SendFailed;
    public event Action<Exception>? RenderingFailed;
    public event Action? GroupSetupRequested;

    public async Task LoadCachedStateAsync(CancellationToken cancellationToken = default)
    {
        if (_cachedStateLoaded)
        {
            return;
        }

        var preferences = await _preferencesStore.LoadAsync(cancellationToken);
        bool startAtLogin = _startup.IsEnabled();
        if (startAtLogin)
        {
            _startup.UpgradeEnabledRegistration();
        }
        preferences = preferences with { StartAtLogin = startAtLogin };
        SetState(_state with { Preferences = preferences });
        _cachedStateLoaded = true;
    }

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        await LoadCachedStateAsync(cancellationToken);
        AppPreferences preferences = _state.Preferences;

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
            StartupDiagnostics.Stage("server-configuration result=missing");
#if DEBUG
            StartPreviewOverlay(preferences);
            SetState(_state with
            {
                ErrorMessage = _validationMode
                    ? I18n.Get("development.metricsPreview")
                    : I18n.Get("development.localPreview"),
            });
#else
            SetState(_state with
            {
                ErrorMessage = I18n.Get("error.serverNotConfigured"),
            });
#endif
            return;
        }

        var auth = new SupabaseAnonymousAuthService(configuration, _credentialStore);
        StartupDiagnostics.Stage("auth-session-read-started");
        var stored = await _credentialStore.ReadAsync(
            CredentialKey.SupabaseSession,
            cancellationToken);
        bool restoringSession = !string.IsNullOrWhiteSpace(stored);
        StartupDiagnostics.Stage(
            $"auth-session-read-completed result={(restoringSession ? "present" : "missing")}");
        StartupDiagnostics.Stage(
            $"auth-session-bootstrap-started mode={(restoringSession ? "restore" : "create")}");
        await AnonymousSessionBootstrapper.RestoreOrCreateAsync(
            auth,
            hasStoredSession: restoringSession,
            cancellationToken);
        StartupDiagnostics.Stage(
            $"auth-session-bootstrap-completed mode={(restoringSession ? "restore" : "create")}");
        var backend = new SupabaseBackendGateway(configuration, auth, _credentialStore);
        _auth = auth;
        _backend = backend;

        StartupDiagnostics.Stage("server-snapshot-fetch-started");
        var snapshot = await backend.FetchSnapshotAsync(cancellationToken);
        StartupDiagnostics.Stage(
            $"server-snapshot-fetch-completed rooms={snapshot.Rooms.Count} profile={(snapshot.Profile is null ? "missing" : "present")}");
        var activeRoomId = SelectActiveRoom(preferences.ActiveRoomId, snapshot.Rooms);
        _state = _state with { ActiveRoomId = activeRoomId };
        ApplySnapshot(snapshot);
        _state = _state with
        {
            ActiveRoomId = activeRoomId,
            RealtimeConnection = RealtimeConnectionStatus.Disconnected,
            ErrorMessage = null,
        };

        _roomSwitch = new RoomSwitchPipeline(
            PerformRoomSwitchAsync,
            RestoreCommittedRoomAsync,
            CommitRoomSwitch);
        _roomSwitch.InitializeCommittedRoom(activeRoomId);
        _eventPump = PumpBackendEventsAsync();
        StartupDiagnostics.Stage(
            $"realtime-subscription-sync-started rooms={snapshot.Rooms.Count}");
        await backend.SynchronizeRealtimeRoomsAsync(
            RoomEpochs(snapshot.Rooms),
            activeRoomId,
            _localPresence,
            cancellationToken);
        StartupDiagnostics.Stage(
            $"realtime-subscription-sync-completed rooms={snapshot.Rooms.Count}");
        if (activeRoomId is { } roomId)
        {
            StartupDiagnostics.Stage("message-history-fetch-started active=true");
            var history = await backend.FetchRecentMessagesAsync(roomId, cancellationToken);
            _messages.ReplaceConfirmed(roomId, history);
            StartupDiagnostics.Stage(
                $"message-history-fetch-completed result=success count={history.Count}");
        }
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
            Preferences = _state.Preferences with
            {
                OnboardingCompleted = _state.Preferences.OnboardingCompleted,
                CachedNickname = profile.Nickname,
                CachedCharacterId = PixelCharacterCatalog.NormalizeId(profile.CharacterId),
            },
            ErrorMessage = null,
        });
        await PersistPreferencesAsync(cancellationToken);
        ApplyWorldSnapshot();
    }

    public async Task CompleteOnboardingAsync(CancellationToken cancellationToken = default)
    {
        AppPreferences previousPreferences = _state.Preferences;
        SetState(_state with
        {
            Preferences = previousPreferences with { OnboardingCompleted = true },
            ErrorMessage = null,
        });
        try
        {
            await PersistPreferencesAsync(cancellationToken);
        }
        catch
        {
            SetState(_state with { Preferences = previousPreferences });
            throw;
        }
    }

    public async Task CreateRoomAsync(string name, CancellationToken cancellationToken = default)
    {
        EnsureMutationsAvailable();
        SetState(_state with
        {
            GroupOperation = GroupOperation.Creating,
            SwitchingRoomId = null,
            ErrorMessage = null,
        });
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
            SetState(_state with { GroupOperation = GroupOperation.Idle, SwitchingRoomId = null });
        }
    }

    public async Task JoinRoomAsync(string inviteCode, CancellationToken cancellationToken = default)
    {
        EnsureMutationsAvailable();
        SetState(_state with
        {
            GroupOperation = GroupOperation.Joining,
            SwitchingRoomId = null,
            ErrorMessage = null,
        });
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
            SetState(_state with { GroupOperation = GroupOperation.Idle, SwitchingRoomId = null });
        }
    }

    public async Task SwitchRoomAsync(Guid roomId, CancellationToken cancellationToken = default)
    {
        if (_state.GroupOperation is not (GroupOperation.Idle or GroupOperation.Switching))
        {
            throw new InvalidOperationException(I18n.Get("groups.operationBusy"));
        }

        if (_roomSwitch is null
            || _state.ActiveRoomId == roomId
            || _state.Rooms.All(room => room.Id != roomId))
        {
            return;
        }

        long operationGeneration = Interlocked.Increment(ref _groupOperationGeneration);
        SetState(_state with
        {
            GroupOperation = GroupOperation.Switching,
            SwitchingRoomId = roomId,
            ErrorMessage = null,
        });
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
            if (operationGeneration == Volatile.Read(ref _groupOperationGeneration))
            {
                SetState(_state with
                {
                    GroupOperation = GroupOperation.Idle,
                    SwitchingRoomId = null,
                });
            }
        }
    }

    public Task RenameRoomAsync(
        Guid roomId,
        string name,
        CancellationToken cancellationToken = default) =>
        RunRoomMutationAsync(
            token => RequiredBackend().RenameRoomAsync(roomId, name, token),
            cancellationToken);

    public Task RotateInviteCodeAsync(
        Guid roomId,
        CancellationToken cancellationToken = default) =>
        RunRoomMutationAsync(
            token => RequiredBackend().RotateInviteCodeAsync(roomId, token),
            cancellationToken);

    public Task RemoveRoomMemberAsync(
        Guid roomId,
        Guid userId,
        CancellationToken cancellationToken = default) =>
        RunRoomMutationAsync(
            token => RequiredBackend().RemoveRoomMemberAsync(roomId, userId, token),
            cancellationToken);

    public Task DeleteRoomAsync(Guid roomId, CancellationToken cancellationToken = default) =>
        RunRoomMutationAsync(
            token => RequiredBackend().DeleteRoomAsync(roomId, token),
            cancellationToken);

    public Task LeaveRoomAsync(Guid roomId, CancellationToken cancellationToken = default) =>
        RunRoomMutationAsync(
            token => RequiredBackend().LeaveRoomAsync(roomId, token),
            cancellationToken);

    private async Task RunRoomMutationAsync(
        Func<CancellationToken, Task> mutation,
        CancellationToken cancellationToken)
    {
        EnsureMutationsAvailable();
        SetState(_state with
        {
            GroupOperation = GroupOperation.Mutating,
            SwitchingRoomId = null,
            ErrorMessage = null,
        });
        try
        {
            await mutation(cancellationToken);
            await RefreshSnapshotAsync(cancellationToken);
        }
        catch (Exception exception)
        {
            SetState(_state with { ErrorMessage = exception.Message });
            throw;
        }
        finally
        {
            SetState(_state with { GroupOperation = GroupOperation.Idle, SwitchingRoomId = null });
        }
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
            throw new InvalidOperationException(I18n.Get("groups.notFound"));
        }
        if (!room.InviteCodeReady)
        {
            throw new InvalidOperationException(
                I18n.Get("groups.inviteRevoked"));
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
                I18n.Get("groups.inviteReplaced"));
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
            throw new InvalidOperationException(I18n.Get("composer.activeRoomRequired"));
        }

        var normalized = MessageValidator.Normalize(body);
        if (!MessageValidator.IsValid(normalized))
        {
            throw new ArgumentException(I18n.Get("validation.messageLength"), nameof(body));
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
        catch (Exception exception)
        {
            _bubbles.Remove(id);
            var restored = _messages.Fail(id);
            PublishState();
            ApplyWorldSnapshot();
            if (restored is not null)
            {
                SendFailed?.Invoke(restored, exception);
            }
            throw;
        }
    }

    public async Task SetOverlayVisibleAsync(bool visible, CancellationToken cancellationToken = default)
    {
        SetState(_state with
        {
            Preferences = _state.Preferences with { OverlayVisible = visible },
        });

        if (!visible)
        {
            _overlay?.Dispose();
            _overlay = null;
        }
        else if (_overlay is null)
        {
            if (_backend is null && _previewSnapshot is not null)
            {
                StartPreviewOverlay(_state.Preferences);
            }
            else if (_state.ActiveRoomId is not null)
            {
                StartOverlay(CurrentWorldSnapshot());
            }
        }

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

    public async Task SetRequiresRightClickToThrowAsync(
        bool enabled,
        CancellationToken cancellationToken = default)
    {
        SetState(_state with
        {
            Preferences = _state.Preferences with { RequiresRightClickToThrow = enabled },
        });
        await PersistPreferencesAsync(cancellationToken);
        _overlay?.ConfigureThrowInteraction(enabled, _backend is null || _state.ActiveRoomConnected);
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

    public IReadOnlyList<MonitorOption> GetMonitors() => WindowsMonitorService.GetAll()
        .Select(monitor => new MonitorOption(
            monitor.Identifier,
            monitor.Name,
            monitor.IsPrimary))
        .ToArray();

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
        ArgumentNullException.ThrowIfNull(preference);
        if (!Enum.IsDefined(preference.Edge) || !Enum.IsDefined(preference.Span))
        {
            throw new ArgumentOutOfRangeException(nameof(preference));
        }
        if (preference == _state.Preferences.OverlayRegion)
        {
            return;
        }

        SetState(_state with
        {
            Preferences = _state.Preferences with { OverlayRegion = preference },
        });
        await PersistPreferencesAsync(cancellationToken);
        if (_overlay is null)
        {
            return;
        }

        if (_backend is null && _previewSnapshot is not null)
        {
            StartPreviewOverlay(_state.Preferences);
            return;
        }

        RestartOverlayForRegionChange();
    }

    public void RequestComposer() => ComposerRequested?.Invoke();

    public void RequestCharacterPulse() => PulseRequested?.Invoke();

    public void RequestCharacterThrow(Guid targetUserId) =>
        CharacterThrowRequested?.Invoke(targetUserId);

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
        QueuePulseForWorld(pulse);

        if (_backend is not null)
        {
            await _backend.BroadcastCharacterPulseAsync(
                roomId.Value,
                pulse.Id,
                cancellationToken);
        }
    }

    public async Task ThrowAtCharacterAsync(
        Guid targetUserId,
        CancellationToken cancellationToken = default)
    {
        var roomId = _state.ActiveRoomId ?? _previewRoomId;
        var actor = _state.Profile;
        var actorUserId = actor?.Id ?? _previewUserId;
        var sourceCharacterId = actor?.CharacterId
            ?? _previewSnapshot?.Members.FirstOrDefault(member => member.IsCurrentUser)?.CharacterId;
        if (roomId is null || actorUserId is null || sourceCharacterId is null
            || actorUserId == targetUserId
            || (_backend is not null && !_state.ActiveRoomConnected))
        {
            return;
        }

        var world = CurrentWorldSnapshot();
        var target = world.Members.FirstOrDefault(member => member.Id == targetUserId);
        if (world.RoomId != roomId || target is null
            || !CharacterThrowTargetPolicy.CanTarget(target))
        {
            return;
        }

        var uptime = TimeSpan.FromSeconds(
            Stopwatch.GetTimestamp() / (double)Stopwatch.Frequency);
        if (!_throwCooldown.Accept(roomId.Value, actorUserId.Value, uptime))
        {
            return;
        }

        var characterThrow = new CharacterThrowEvent(
            Guid.NewGuid(),
            roomId.Value,
            actorUserId.Value,
            targetUserId,
            sourceCharacterId);
        QueueThrowForWorld(characterThrow);
        if (_backend is not null)
        {
            try
            {
                await _backend.BroadcastCharacterThrowAsync(
                    roomId.Value,
                    characterThrow.Id,
                    targetUserId,
                    cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
            }
            catch (Exception exception)
            {
                Trace.TraceError("SIDEY character throw broadcast failed: {0}", exception);
            }
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
            _localPresence,
            cancellationToken);
        return await backend.FetchRecentMessagesAsync(roomId, cancellationToken);
    }

    private Task RestoreCommittedRoomAsync(Guid? roomId, CancellationToken cancellationToken) =>
        RequiredBackend().SynchronizeRealtimeRoomsAsync(
            RoomEpochs(_state.Rooms),
            roomId,
            _localPresence,
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
        if (_overlay is null && _state.Preferences.OverlayVisible)
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
                        bool isActiveRoom = message.Message.RoomId == _state.ActiveRoomId;
                        StartupDiagnostics.Stage(
                            $"realtime-message-received active={isActiveRoom.ToString().ToLowerInvariant()}");
                        _messages.Confirm(message.Message);
                        StartupDiagnostics.Stage("message-ledger-confirmed");
                        _bubbles.Show(
                            message.Message.SenderId,
                            message.Message.Id,
                            message.Message.Body);
                        StartupDiagnostics.Stage(
                            $"message-bubble-enqueued active={isActiveRoom.ToString().ToLowerInvariant()} quiet={_state.Preferences.QuietMode.ToString().ToLowerInvariant()}");
                        if (message.Message.SenderId != _state.Profile?.Id
                            && (!isActiveRoom || _state.Preferences.QuietMode))
                        {
                            _unreadByRoom[message.Message.RoomId] = Math.Min(
                                99,
                                _unreadByRoom.GetValueOrDefault(message.Message.RoomId) + 1);
                        }
                        PublishState();
                        ApplyWorldSnapshot("message");
                        break;
                    case BackendEvent.MessageDeleted deleted:
                        _messages.Remove(deleted.RoomId, deleted.MessageId);
                        _bubbles.Remove(deleted.MessageId);
                        PublishState();
                        ApplyWorldSnapshot();
                        break;
                    case BackendEvent.MessagesReplaced replaced:
                        StartupDiagnostics.Stage(
                            $"realtime-messages-reconciled active={(replaced.RoomId == _state.ActiveRoomId).ToString().ToLowerInvariant()}");
                        _messages.ReplaceConfirmed(replaced.RoomId, replaced.Messages);
                        if (replaced.RoomId == _state.ActiveRoomId)
                        {
                            _bubbles.Clear();
                        }
                        PublishState();
                        ApplyWorldSnapshot();
                        break;
                    case BackendEvent.PresenceChanged presence:
                        StartupDiagnostics.Stage(
                            $"realtime-presence state={presence.State.ToString().ToLowerInvariant()}");
                        UpdatePresence(
                            presence.RoomId,
                            presence.UserId,
                            presence.State);
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
                            QueuePulseForWorld(pulsed.Pulse);
                        }
                        break;
                    case BackendEvent.CharacterThrown thrown:
                        var characterThrow = thrown.Throw;
                        var activeRoom = _state.ActiveRoomId is { } activeRoomId
                            ? _state.Rooms.FirstOrDefault(room => room.Id == activeRoomId)
                            : null;
                        if (activeRoom?.Id == characterThrow.RoomId
                            && characterThrow.ActorUserId != characterThrow.TargetUserId
                            && activeRoom.Members.Any(member => member.UserId == characterThrow.ActorUserId)
                            && activeRoom.Members.Any(member => member.UserId == characterThrow.TargetUserId)
                            && _throwCooldown.Accept(
                                characterThrow.RoomId,
                                characterThrow.ActorUserId,
                                TimeSpan.FromSeconds(
                                    Stopwatch.GetTimestamp() / (double)Stopwatch.Frequency)))
                        {
                            QueueThrowForWorld(characterThrow);
                        }
                        break;
                    case BackendEvent.ConnectionChanged connection:
                        StartupDiagnostics.Stage(
                            $"realtime-connection transport={connection.Status.TransportConnected.ToString().ToLowerInvariant()} "
                            + $"active-room={connection.Status.ActiveRoomTransportConnected.ToString().ToLowerInvariant()} "
                            + $"reconciled={connection.Status.RecoveryReconciled.ToString().ToLowerInvariant()}");
                        SetRealtimeConnection(connection.Status);
                        break;
                    case BackendEvent.Diagnostic diagnostic:
                        StartupDiagnostics.Stage(diagnostic.Stage);
                        break;
                    case BackendEvent.TechnicalError error:
                        StartupDiagnostics.Stage("realtime-technical-error");
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
            StartupDiagnostics.NonFatal("backend-event-pump", exception);
            SetState(_state with
            {
                RealtimeConnection = RealtimeConnectionStatus.Disconnected,
                ErrorMessage = exception.Message,
            });
        }
    }

    private async Task PumpActivityAsync()
    {
        await foreach (var presence in _activityMonitor.ObserveAsync(_lifetime.Token))
        {
            _localPresence = presence;
            if (_state.Profile is { } profile && _state.ActiveRoomId is { } activeRoomId)
            {
                UpdateMember(activeRoomId, profile.Id, member => member with
                {
                    Presence = _localPresence,
                });
            }

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
                SetRealtimeConnection(RealtimeConnectionStatus.Disconnected);
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

    private void UpdatePresence(Guid roomId, Guid userId, PresenceState presence)
    {
        var key = (roomId, userId);
        _basePresence[key] = presence;
        if (presence == PresenceState.Offline)
        {
            _typing.Remove(key);
        }

        UpdateMember(roomId, userId, member => member with
        {
            Presence = LocalPresenceProjection.ForMember(
                userId,
                _state.Profile?.Id ?? Guid.Empty,
                presence,
                _localPresence),
        });
    }

    private void SetRealtimeConnection(RealtimeConnectionStatus status)
    {
        bool activeRoomConnectionChanged =
            status.ActiveRoomTransportConnected != _state.ActiveRoomConnected;
        if (activeRoomConnectionChanged && !status.ActiveRoomTransportConnected)
        {
            _typing.Clear();
        }

        var currentUserId = _state.Profile?.Id;
        IReadOnlyList<Room> rooms = activeRoomConnectionChanged
            ? _state.Rooms.Select(room => room with
            {
                Members = room.Members.Select(member =>
                {
                    var key = (room.Id, member.UserId);
                    if (status.ActiveRoomTransportConnected)
                    {
                        return member with
                        {
                            Presence = member.UserId == currentUserId
                                ? _localPresence
                                : _basePresence.GetValueOrDefault(key, PresenceState.Offline),
                        };
                    }

                    if (member.Presence == PresenceState.Offline)
                    {
                        return member;
                    }

                    if (member.UserId != currentUserId)
                    {
                        _basePresence[key] = PresenceState.Offline;
                    }
                    return member with { Presence = PresenceState.Reconnecting };
                }).ToArray(),
            }).ToArray()
            : _state.Rooms;

        SetState(_state with { Rooms = rooms, RealtimeConnection = status });
        _overlay?.ConfigureThrowInteraction(
            _state.Preferences.RequiresRightClickToThrow,
            status.ActiveRoomTransportConnected);
        if (_overlay is null
            && _state.ActiveRoomId is not null
            && _state.Preferences.OverlayVisible)
        {
            StartOverlay(CurrentWorldSnapshot());
        }
        else
        {
            ApplyWorldSnapshot();
        }
    }

    private void ApplySnapshot(BackendSnapshot snapshot)
    {
        var activeRoomId = SelectActiveRoom(_state.ActiveRoomId, snapshot.Rooms);
        Profile? profile = snapshot.Profile is null
            ? null
            : snapshot.Profile with
            {
                CharacterId = PixelCharacterCatalog.SelectableId(
                    snapshot.Profile.CharacterId,
                    snapshot.ActiveEntitlementKeys),
            };
        PresenceState? KnownPresence(Guid roomId, Guid userId) =>
            _basePresence.TryGetValue((roomId, userId), out var presence)
                ? presence
                : null;
        var projectedRooms = snapshot.Rooms.Select(room => room with
        {
            Members = room.Members.Select(member => member with
            {
                CharacterId = member.UserId == snapshot.CurrentUserId && profile is not null
                    ? profile.CharacterId
                    : member.CharacterId,
                Presence = LocalPresenceProjection.ForSnapshotMember(
                    member.UserId,
                    snapshot.CurrentUserId,
                    member.Presence,
                    KnownPresence(room.Id, member.UserId),
                    _localPresence),
            }).ToArray(),
        }).ToArray();
        var validPresenceKeys = projectedRooms
            .SelectMany(room => room.Members.Select(member => (room.Id, member.UserId)))
            .ToHashSet();
        foreach (var key in _basePresence.Keys.Where(key => !validPresenceKeys.Contains(key)).ToArray())
        {
            _basePresence.Remove(key);
        }
        foreach (var room in snapshot.Rooms)
        {
            foreach (var member in room.Members)
            {
                _basePresence.TryAdd((room.Id, member.UserId), member.Presence);
            }
        }
        var roomIds = snapshot.Rooms.Select(room => room.Id).ToHashSet();
        foreach (var removedRoomId in _unreadByRoom.Keys.Where(id => !roomIds.Contains(id)).ToArray())
        {
            _unreadByRoom.Remove(removedRoomId);
        }
        _state = _state with
        {
            Profile = profile,
            Rooms = projectedRooms,
            ActiveEntitlementKeys = snapshot.ActiveEntitlementKeys,
            ActiveRoomId = activeRoomId,
            Preferences = _state.Preferences with
            {
                OnboardingCompleted = _state.Preferences.OnboardingCompleted,
                ActiveRoomId = activeRoomId,
                CachedNickname = profile?.Nickname ?? _state.Preferences.CachedNickname,
                CachedCharacterId = profile is null
                    ? _state.Preferences.CachedCharacterId
                    : profile.CharacterId,
            },
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
        await RequiredBackend().SynchronizeRealtimeRoomsAsync(
            RoomEpochs(snapshot.Rooms),
            _state.ActiveRoomId,
            _localPresence,
            cancellationToken);
        if (_overlay is null
            && _state.ActiveRoomConnected
            && _state.ActiveRoomId is not null
            && _state.Preferences.OverlayVisible)
        {
            StartOverlay(CurrentWorldSnapshot());
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
        if (preferences.OverlayVisible)
        {
            StartOverlay(snapshot, _validationMode ? ids.ToHashSet(StringComparer.Ordinal) : null);
        }
    }

    private void StartOverlay(WorldSnapshot snapshot, IReadOnlySet<string>? validationIds = null)
    {
        if (!_state.Preferences.OverlayVisible)
        {
            return;
        }

        _overlay?.Dispose();
        try
        {
            _overlay = NativePixelWorldSession.Start(
                _state.Preferences.OverlayRegion,
                snapshot,
                RequestComposer,
                RequestCharacterPulse,
                RequestCharacterThrow,
                _state.Preferences.RequiresRightClickToThrow,
                _backend is null || _state.ActiveRoomConnected,
                exception => RenderingFailed?.Invoke(exception),
                new NativePixelWorldSessionOptions(
                    ValidationCharacterIds: validationIds,
                    CollectValidationMetrics: validationIds is not null,
                    MessageBubblesPresented: count => StartupDiagnostics.Stage(
                        $"overlay-message-presented count={count}"),
                    Diagnostic: StartupDiagnostics.Stage,
                    DiagnosticFailure: StartupDiagnostics.NonFatal,
                    RendererPerformanceSampled: (average, maximum, frames, skipped) =>
                        StartupDiagnostics.Stage(
                            $"renderer-health frames={frames} "
                            + $"average-ms={average.ToString("F2", CultureInfo.InvariantCulture)} "
                            + $"maximum-ms={maximum.ToString("F2", CultureInfo.InvariantCulture)} "
                            + $"skipped={skipped}")));
        }
        catch (Exception exception)
        {
            StartupDiagnostics.NonFatal("overlay-window-create", exception);
            throw;
        }
        StartupDiagnostics.Stage("overlay-started");
    }

    private void RestartOverlayForRegionChange()
    {
        var snapshot = CurrentWorldSnapshot();
        _overlay?.Dispose();
        _overlay = null;
        StartOverlay(snapshot);
    }

    private void ApplyWorldSnapshot(string? diagnosticContext = null)
    {
        if (_overlay is null)
        {
            if (diagnosticContext is not null)
            {
                StartupDiagnostics.Stage(
                    $"overlay-snapshot-skipped context={diagnosticContext} reason=not-started");
            }
            return;
        }
        _bubbles.Prune();
        WorldSnapshot snapshot = CurrentWorldSnapshot();
        if (diagnosticContext is not null)
        {
            StartupDiagnostics.Stage(
                $"overlay-snapshot-dispatched context={diagnosticContext} visible={_overlay.IsVisible.ToString().ToLowerInvariant()} members={snapshot.Members.Count} bubbles={snapshot.Bubbles.Count}");
        }
        _overlay.Apply(snapshot);
        if (diagnosticContext is not null)
        {
            StartupDiagnostics.Stage($"overlay-snapshot-accepted context={diagnosticContext}");
        }
        _pendingPulses.Clear();
        _pendingThrows.Clear();
    }

    private void QueuePulseForWorld(CharacterPulseEvent pulse)
    {
        if (_overlay is null)
        {
            return;
        }

        _pendingPulses.Add(pulse);
        ApplyWorldSnapshot();
    }

    private void QueueThrowForWorld(CharacterThrowEvent characterThrow)
    {
        if (_overlay is null)
        {
            return;
        }

        _pendingThrows.Add(characterThrow);
        ApplyWorldSnapshot();
    }

    private WorldSnapshot CurrentWorldSnapshot()
    {
        if (_backend is null && _previewSnapshot is { } preview)
        {
            return preview with
            {
                Pulses = _pendingPulses.ToArray(),
                Throws = _pendingThrows.ToArray(),
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
            _pendingPulses.ToArray(),
            _pendingThrows.ToArray(),
            _state.Preferences.OverlayRegion.Edge,
            _state.Preferences.InstallationSeed);
    }

    private async Task PersistPreferencesAsync(CancellationToken cancellationToken) =>
        await _preferencesStore.SaveAsync(_state.Preferences, cancellationToken).ConfigureAwait(false);

    private IBackendGateway RequiredBackend() =>
        _backend ?? throw new InvalidOperationException(I18n.Get("error.serverConnectionNotConfigured"));

    private void EnsureMutationsAvailable()
    {
        if (_state.GroupOperation != GroupOperation.Idle)
        {
            throw new InvalidOperationException(I18n.Get("groups.operationBusy"));
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
                RealtimeConnection = RealtimeConnectionStatus.Disconnected,
                ErrorMessage = I18n.Format("error.typingUpdateFailed", exception.Message),
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
            SetState(_state with { ErrorMessage = I18n.Format("error.preferencesSaveFailed", exception.Message) });
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
