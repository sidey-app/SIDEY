using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Net.Sockets;
using System.Runtime.CompilerServices;
using System.Security.Authentication;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Channels;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Sidey.Core.Realtime;

namespace Sidey.Infrastructure;

public sealed class SupabaseBackendGateway : IBackendGateway, IAsyncDisposable
{
    private static readonly TimeSpan StructuralCoalescingWindow = TimeSpan.FromMilliseconds(150);
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private readonly SupabaseRuntimeConfiguration _configuration;
    private readonly ICredentialStore _credentials;
    private readonly IAuthSessionAccessor _sessions;
    private readonly HttpClient _httpClient;
    private readonly bool _ownsHttpClient;
    private readonly SupabaseRealtimeTransport _realtime;
    private IReadOnlyDictionary<Guid, long> _roomEpochs = new Dictionary<Guid, long>();
    private Guid? _activeRoomId;

    public SupabaseBackendGateway(
        SupabaseRuntimeConfiguration configuration,
        SupabaseAnonymousAuthService auth,
        ICredentialStore credentials,
        HttpClient? httpClient = null)
    {
        _configuration = configuration ?? throw new ArgumentNullException(nameof(configuration));
        _sessions = auth ?? throw new ArgumentNullException(nameof(auth));
        _credentials = credentials ?? throw new ArgumentNullException(nameof(credentials));
        _httpClient = httpClient ?? new HttpClient();
        _ownsHttpClient = httpClient is null;
        _realtime = new SupabaseRealtimeTransport(configuration, auth);
    }

    public async Task<BackendSnapshot> FetchSnapshotAsync(CancellationToken cancellationToken = default)
    {
        var session = await RequiredSessionAsync(cancellationToken).ConfigureAwait(false);
        var profileTask = GetAsync<DatabaseProfile[]>(
            $"/rest/v1/profiles?id=eq.{session.UserId:D}&select=*",
            cancellationToken);
        var roomsTask = GetAsync<DatabaseRoom[]>(
            "/rest/v1/rooms?select=*&order=created_at.asc",
            cancellationToken);
        var membershipsTask = GetAsync<DatabaseMembership[]>(
            "/rest/v1/room_members?select=*&order=joined_at.asc",
            cancellationToken);
        var profilesTask = GetAsync<DatabaseProfile[]>(
            "/rest/v1/profiles?select=*",
            cancellationToken);
        var entitlementsTask = LoadActiveEntitlementKeysIfAvailableAsync(cancellationToken);

        await Task.WhenAll(profileTask, roomsTask, membershipsTask, profilesTask, entitlementsTask)
            .ConfigureAwait(false);
        var peers = (await profilesTask.ConfigureAwait(false)).ToDictionary(profile => profile.Id);
        var memberships = (await membershipsTask.ConfigureAwait(false))
            .GroupBy(membership => membership.RoomId)
            .ToDictionary(group => group.Key, group => group.ToArray());
        var rooms = (await roomsTask.ConfigureAwait(false)).Select(room => new Room(
            room.Id,
            room.Name,
            room.OwnerId,
            memberships.GetValueOrDefault(room.Id, [])
                .Select(membership =>
                {
                    peers.TryGetValue(membership.UserId, out var peer);
                    return new RoomMember(
                        membership.UserId,
                        peer?.Nickname ?? I18n.Get("common.friend"),
                        PixelCharacterCatalog.NormalizeId(peer?.CharacterId),
                        PresenceState.Offline);
                })
                .ToArray(),
            room.InviteCodeHint,
            room.InviteCodeReady,
            room.RealtimeEpoch)).ToArray();
        foreach (var room in rooms.Where(room => !room.InviteCodeReady))
        {
            await _credentials.DeleteInviteCodeAsync(room.Id, cancellationToken).ConfigureAwait(false);
        }
        var profile = (await profileTask.ConfigureAwait(false)).FirstOrDefault();
        IReadOnlySet<string> activeEntitlementKeys = PixelCharacterCatalog.ResolveActiveEntitlementKeys(
            await entitlementsTask.ConfigureAwait(false),
            profile?.CharacterId);
        return new BackendSnapshot(
            profile is null
                ? null
                : new Profile(
                    profile.Id,
                    profile.Nickname,
                    PixelCharacterCatalog.NormalizeId(profile.CharacterId)),
            rooms,
            session.UserId,
            activeEntitlementKeys);
    }

    /// <summary>
    /// Commerce is optional. A missing or temporarily unavailable commerce
    /// schema must not turn the core messenger snapshot into a connection failure.
    /// </summary>
    private async Task<IReadOnlySet<string>?> LoadActiveEntitlementKeysIfAvailableAsync(
        CancellationToken cancellationToken)
    {
        try
        {
            DatabaseCommerceEntitlement[] rows = await GetAsync<DatabaseCommerceEntitlement[]>(
                "/rest/v1/commerce_entitlements?status=eq.active&select=entitlement_key,status",
                cancellationToken).ConfigureAwait(false);
            return rows.Select(row => row.EntitlementKey).ToHashSet(StringComparer.Ordinal);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return null;
        }
    }

    public async Task<Profile> SaveProfileAsync(
        string nickname,
        string characterId,
        CancellationToken cancellationToken = default)
    {
        if (!ProfileValidator.IsValidNickname(nickname))
        {
            throw new ArgumentException(I18n.Get("validation.nicknameLength"), nameof(nickname));
        }

        var row = await RpcSingleAsync<DatabaseProfile>(
            "upsert_profile",
            new
            {
                p_nickname = ProfileValidator.NormalizeNickname(nickname),
                p_character_id = PixelCharacterCatalog.NormalizeId(characterId),
            },
            cancellationToken).ConfigureAwait(false);
        return new Profile(row.Id, row.Nickname, PixelCharacterCatalog.NormalizeId(row.CharacterId));
    }

    public async Task<CreateRoomResult> CreateRoomAsync(
        string name,
        CancellationToken cancellationToken = default)
    {
        ValidateRoomName(name);
        var row = await RpcSingleAsync<CreateRoomRow>(
            "create_room",
            new { p_name = RoomNameValidator.Normalize(name) },
            cancellationToken).ConfigureAwait(false);
        await _credentials.WriteInviteCodeAsync(row.RoomId, row.InviteCode, cancellationToken)
            .ConfigureAwait(false);
        var snapshot = await FetchSnapshotAsync(cancellationToken).ConfigureAwait(false);
        var room = snapshot.Rooms.SingleOrDefault(room => room.Id == row.RoomId)
            ?? throw new InvalidDataException(I18n.Get("backend.createdRoomMissing"));
        return new CreateRoomResult(room, row.InviteCode);
    }

    public async Task<Room> JoinRoomAsync(
        string inviteCode,
        CancellationToken cancellationToken = default)
    {
        var normalized = inviteCode.Trim().ToUpperInvariant();
        if (normalized.Length == 0)
        {
            throw new ArgumentException(I18n.Get("onboarding.inviteRequired"), nameof(inviteCode));
        }

        var row = await RpcSingleAsync<JoinRoomRow>(
            "join_room",
            new { p_invite_code = normalized },
            cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrEmpty(row.ErrorCode))
        {
            throw new InvalidOperationException(I18n.Format("backend.joinFailed", row.ErrorCode));
        }

        if (row.RoomId is not { } roomId)
        {
            throw new InvalidDataException(I18n.Get("backend.joinRoomIdMissing"));
        }

        await _credentials.WriteInviteCodeAsync(roomId, normalized, cancellationToken)
            .ConfigureAwait(false);
        var snapshot = await FetchSnapshotAsync(cancellationToken).ConfigureAwait(false);
        return snapshot.Rooms.SingleOrDefault(room => room.Id == roomId)
            ?? throw new InvalidDataException(I18n.Get("backend.joinedRoomMissing"));
    }

    public async Task LeaveRoomAsync(Guid roomId, CancellationToken cancellationToken = default)
    {
        await RpcNoResultAsync("leave_room", new { p_room_id = roomId }, cancellationToken)
            .ConfigureAwait(false);
        await _credentials.DeleteInviteCodeAsync(roomId, cancellationToken).ConfigureAwait(false);
    }

    public Task RenameRoomAsync(
        Guid roomId,
        string name,
        CancellationToken cancellationToken = default)
    {
        ValidateRoomName(name);
        return RpcNoResultAsync(
            "rename_room",
            new { p_room_id = roomId, p_name = RoomNameValidator.Normalize(name) },
            cancellationToken);
    }

    public async Task<string> RotateInviteCodeAsync(
        Guid roomId,
        CancellationToken cancellationToken = default)
    {
        var inviteCode = await RpcSingleAsync<string>(
            "rotate_invite_code",
            new { p_room_id = roomId },
            cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(inviteCode))
        {
            throw new InvalidDataException(I18n.Get("backend.emptyInviteCode"));
        }

        await _credentials.WriteInviteCodeAsync(roomId, inviteCode, cancellationToken)
            .ConfigureAwait(false);
        return inviteCode;
    }

    public Task RemoveRoomMemberAsync(
        Guid roomId,
        Guid userId,
        CancellationToken cancellationToken = default) =>
        RpcNoResultAsync(
            "remove_room_member",
            new { p_room_id = roomId, p_user_id = userId },
            cancellationToken);

    public async Task DeleteRoomAsync(Guid roomId, CancellationToken cancellationToken = default)
    {
        await RpcNoResultAsync("delete_room", new { p_room_id = roomId }, cancellationToken)
            .ConfigureAwait(false);
        await _credentials.DeleteInviteCodeAsync(roomId, cancellationToken).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<ChatMessage>> FetchRecentMessagesAsync(
        Guid roomId,
        CancellationToken cancellationToken = default)
    {
        var page = await FetchMessagePageAsync(
            roomId,
            before: null,
            limit: 50,
            cancellationToken).ConfigureAwait(false);
        return page.Messages.Reverse().ToArray();
    }

    public async Task<MessageHistoryPage> FetchMessagePageAsync(
        Guid roomId,
        MessageHistoryCursor? before,
        int limit = 50,
        CancellationToken cancellationToken = default)
    {
        var boundedLimit = Math.Clamp(limit, 1, 50);
        var cutoff = Uri.EscapeDataString(
            (DateTimeOffset.UtcNow - MessageLedger.ConfirmedRetention)
            .UtcDateTime
            .ToString("O"));
        var beforeFilter = string.Empty;
        if (before is { } cursor)
        {
            var timestamp = Uri.EscapeDataString(cursor.CreatedAt.UtcDateTime.ToString("O"));
            beforeFilter =
                $"&or=(created_at.lt.{timestamp},and(created_at.eq.{timestamp},id.lt.{cursor.Id:D}))";
        }

        var rows = await GetAsync<DatabaseMessage[]>(
            $"/rest/v1/messages?room_id=eq.{roomId:D}&created_at=gte.{cutoff}{beforeFilter}" +
            $"&select=*&order=created_at.desc,id.desc&limit={boundedLimit + 1}",
            cancellationToken).ConfigureAwait(false);
        var messages = rows.Take(boundedLimit).Select(MapMessage).ToArray();
        MessageHistoryCursor? nextCursor = rows.Length > boundedLimit && messages.LastOrDefault() is { } last
            ? new MessageHistoryCursor(last.CreatedAt, last.Id)
            : null;
        return new MessageHistoryPage(messages, nextCursor);
    }

    public async Task<ChatMessage> SendMessageAsync(
        Guid id,
        Guid roomId,
        string body,
        CancellationToken cancellationToken = default)
    {
        var normalized = MessageValidator.Normalize(body);
        if (!MessageValidator.IsValid(normalized))
        {
            throw new ArgumentException(I18n.Get("validation.messageLength"), nameof(body));
        }

        var row = await RpcSingleAsync<DatabaseMessage>(
            "send_message",
            new { p_id = id, p_room_id = roomId, p_body = normalized },
            cancellationToken).ConfigureAwait(false);
        return MapMessage(row);
    }

    public Task PublishPresenceAsync(
        Guid roomId,
        PresenceState state,
        CancellationToken cancellationToken = default) =>
        _realtime.PublishPresenceAsync(roomId, state, cancellationToken);

    public async Task BroadcastTypingAsync(
        Guid roomId,
        bool active,
        bool keepalive,
        CancellationToken cancellationToken = default)
    {
        _ = keepalive;
        await BroadcastRoomEventAsync(
            roomId,
            active ? "typing_start" : "typing_stop",
            eventId: null,
            cancellationToken).ConfigureAwait(false);
    }

    public async Task BroadcastCharacterPulseAsync(
        Guid roomId,
        Guid eventId,
        CancellationToken cancellationToken = default)
    {
        await BroadcastRoomEventAsync(
            roomId,
            "character_pulse",
            eventId,
            cancellationToken).ConfigureAwait(false);
    }

    public Task BroadcastCharacterThrowAsync(
        Guid roomId,
        Guid eventId,
        Guid targetUserId,
        CancellationToken cancellationToken = default)
    {
        if (!_roomEpochs.TryGetValue(roomId, out var realtimeEpoch))
        {
            throw new InvalidOperationException(I18n.Get("backend.realtimeEpochMissing"));
        }

        return RpcNoResultAsync(
            "broadcast_character_throw",
            new
            {
                p_room_id = roomId,
                p_realtime_epoch = realtimeEpoch,
                p_event_id = eventId,
                p_target_user_id = targetUserId,
            },
            cancellationToken);
    }

    public async Task SynchronizeRealtimeRoomsAsync(
        IReadOnlyDictionary<Guid, long> roomEpochs,
        Guid? activeRoomId,
        PresenceState localPresence,
        CancellationToken cancellationToken = default)
    {
        await _realtime.SynchronizeAsync(
            roomEpochs,
            activeRoomId,
            localPresence,
            cancellationToken).ConfigureAwait(false);
        _roomEpochs = roomEpochs.ToDictionary(pair => pair.Key, pair => pair.Value);
        _activeRoomId = activeRoomId is { } id && roomEpochs.ContainsKey(id) ? id : null;
    }

    public async IAsyncEnumerable<BackendEvent> SubscribeAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var output = Channel.CreateBounded<BackendEvent>(new BoundedChannelOptions(256)
        {
            FullMode = BoundedChannelFullMode.Wait,
            SingleReader = true,
            SingleWriter = false,
        });
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var pump = PumpEventsAsync(output.Writer, linked.Token);
        try
        {
            await foreach (var backendEvent in output.Reader.ReadAllAsync(cancellationToken))
            {
                yield return backendEvent;
            }
        }
        finally
        {
            linked.Cancel();
            try
            {
                await pump.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }
        }
    }

    public async ValueTask DisposeAsync()
    {
        await _realtime.DisposeAsync().ConfigureAwait(false);
        if (_ownsHttpClient)
        {
            _httpClient.Dispose();
        }
    }

    private async Task PumpEventsAsync(
        ChannelWriter<BackendEvent> output,
        CancellationToken cancellationToken)
    {
        CancellationTokenSource? structuralDelay = null;
        try
        {
            await foreach (var backendEvent in _realtime.ReadEventsAsync(cancellationToken))
            {
                if (backendEvent is BackendEvent.MessageChanged change)
                {
                    try
                    {
                        await output.WriteAsync(
                            new BackendEvent.Diagnostic(
                                $"realtime-message-change-received operation={change.Operation.ToLowerInvariant()}"),
                            cancellationToken).ConfigureAwait(false);
                        await HandleMessageChangeAsync(change, output, cancellationToken)
                            .ConfigureAwait(false);
                    }
                    catch (Exception exception) when (exception is not OperationCanceledException)
                    {
                        await output.WriteAsync(
                            new BackendEvent.Diagnostic(
                                $"message-recheck-error {FailureDiagnostic(exception)}"),
                            cancellationToken).ConfigureAwait(false);
                        await output.WriteAsync(
                            new BackendEvent.TechnicalError(
                                I18n.Format("backend.messageRecheckFailed", exception.Message)),
                            cancellationToken).ConfigureAwait(false);
                    }
                    continue;
                }

                if (backendEvent is BackendEvent.MessagesInvalidated invalidated)
                {
                    try
                    {
                        var messages = await FetchRecentMessagesAsync(
                            invalidated.RoomId,
                            cancellationToken).ConfigureAwait(false);
                        await output.WriteAsync(
                            new BackendEvent.MessagesReplaced(invalidated.RoomId, messages),
                            cancellationToken).ConfigureAwait(false);
                    }
                    catch (Exception exception) when (exception is not OperationCanceledException)
                    {
                        await output.WriteAsync(
                            new BackendEvent.Diagnostic(
                                $"expired-messages-error {FailureDiagnostic(exception)}"),
                            cancellationToken).ConfigureAwait(false);
                        await output.WriteAsync(
                            new BackendEvent.TechnicalError(
                                I18n.Format("backend.expiredMessagesFailed", exception.Message)),
                            cancellationToken).ConfigureAwait(false);
                    }
                    continue;
                }

                if (backendEvent is BackendEvent.RoomStructureChanged)
                {
                    structuralDelay?.Cancel();
                    structuralDelay?.Dispose();
                    structuralDelay = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                    _ = EmitCoalescedSnapshotAsync(output, structuralDelay.Token);
                    continue;
                }

                if (backendEvent is BackendEvent.ReconciliationRequired)
                {
                    await EmitReconciliationWithRetryAsync(output, cancellationToken)
                        .ConfigureAwait(false);
                    continue;
                }

                if (backendEvent is BackendEvent.ConnectionChanged { Connected: true })
                {
                    await EmitReconciliationWithRetryAsync(output, cancellationToken)
                        .ConfigureAwait(false);
                }

                await output.WriteAsync(backendEvent, cancellationToken).ConfigureAwait(false);
            }
        }
        finally
        {
            structuralDelay?.Cancel();
            structuralDelay?.Dispose();
            output.TryComplete();
        }
    }

    private async Task EmitReconciliationWithRetryAsync(
        ChannelWriter<BackendEvent> output,
        CancellationToken cancellationToken)
    {
        for (var attempt = 0; ; attempt++)
        {
            try
            {
                await EmitReconciliationAsync(output, cancellationToken).ConfigureAwait(false);
                return;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception)
            {
                await output.WriteAsync(
                    new BackendEvent.Diagnostic(
                        $"realtime-reconciliation-error {FailureDiagnostic(exception)}"),
                    cancellationToken).ConfigureAwait(false);
                await output.WriteAsync(
                    new BackendEvent.TechnicalError(
                        I18n.Format("backend.realtimeResyncFailed", exception.Message)),
                    cancellationToken).ConfigureAwait(false);
                await output.WriteAsync(
                    new BackendEvent.ConnectionChanged(false),
                    cancellationToken).ConfigureAwait(false);
                await Task.Delay(
                    RealtimeRecoveryPolicy.DelayForAttempt(attempt + 1),
                    cancellationToken).ConfigureAwait(false);
            }
        }
    }

    private async Task EmitReconciliationAsync(
        ChannelWriter<BackendEvent> output,
        CancellationToken cancellationToken)
    {
        var snapshot = await FetchSnapshotAsync(cancellationToken).ConfigureAwait(false);
        await output.WriteAsync(
            new BackendEvent.SnapshotReceived(snapshot),
            cancellationToken).ConfigureAwait(false);
        if (_activeRoomId is { } activeRoomId
            && snapshot.Rooms.Any(room => room.Id == activeRoomId))
        {
            await output.WriteAsync(
                new BackendEvent.MessagesReplaced(
                    activeRoomId,
                    await FetchRecentMessagesAsync(activeRoomId, cancellationToken)
                        .ConfigureAwait(false)),
                cancellationToken).ConfigureAwait(false);
        }
    }

    private async Task HandleMessageChangeAsync(
        BackendEvent.MessageChanged change,
        ChannelWriter<BackendEvent> output,
        CancellationToken cancellationToken)
    {
        if (change.Operation == "DELETE")
        {
            await output.WriteAsync(
                new BackendEvent.Diagnostic("message-delete-forwarded"),
                cancellationToken).ConfigureAwait(false);
            await output.WriteAsync(
                new BackendEvent.MessageDeleted(change.RoomId, change.MessageId),
                cancellationToken).ConfigureAwait(false);
            return;
        }

        if (change.Operation is not ("INSERT" or "UPDATE"))
        {
            return;
        }

        await output.WriteAsync(
            new BackendEvent.Diagnostic("message-recheck-started"),
            cancellationToken).ConfigureAwait(false);
        DatabaseMessage[] rows;
        try
        {
            rows = await GetAsync<DatabaseMessage[]>(
                $"/rest/v1/messages?room_id=eq.{change.RoomId:D}&id=eq.{change.MessageId:D}&select=*&limit=1",
                cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            await output.WriteAsync(
                new BackendEvent.Diagnostic("message-recheck-completed result=failed"),
                cancellationToken).ConfigureAwait(false);
            throw;
        }
        if (rows.FirstOrDefault() is { } row)
        {
            await output.WriteAsync(
                new BackendEvent.Diagnostic("message-recheck-completed result=found"),
                cancellationToken).ConfigureAwait(false);
            await output.WriteAsync(
                new BackendEvent.MessageReceived(MapMessage(row)),
                cancellationToken).ConfigureAwait(false);
        }
        else
        {
            await output.WriteAsync(
                new BackendEvent.Diagnostic("message-recheck-completed result=missing"),
                cancellationToken).ConfigureAwait(false);
            await output.WriteAsync(
                new BackendEvent.MessageDeleted(change.RoomId, change.MessageId),
                cancellationToken).ConfigureAwait(false);
        }
    }

    private async Task EmitCoalescedSnapshotAsync(
        ChannelWriter<BackendEvent> output,
        CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(StructuralCoalescingWindow, cancellationToken).ConfigureAwait(false);
            var snapshot = await FetchSnapshotAsync(cancellationToken).ConfigureAwait(false);
            await output.WriteAsync(new BackendEvent.SnapshotReceived(snapshot), cancellationToken)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception exception)
        {
            output.TryWrite(new BackendEvent.Diagnostic(
                $"room-snapshot-error {FailureDiagnostic(exception)}"));
            output.TryWrite(new BackendEvent.TechnicalError(
                I18n.Format("backend.roomSnapshotFailed", exception.Message)));
        }
    }

    private async Task<T> GetAsync<T>(string relativePath, CancellationToken cancellationToken)
    {
        using var request = await CreateRequestAsync(HttpMethod.Get, relativePath, cancellationToken)
            .ConfigureAwait(false);
        using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        return await ReadRequiredAsync<T>(response, cancellationToken).ConfigureAwait(false);
    }

    private static string FailureDiagnostic(Exception exception)
    {
        Exception current = exception;
        while (current.InnerException is { } inner)
        {
            current = inner;
        }

        string category = current switch
        {
            SocketException socket when socket.SocketErrorCode is
                SocketError.HostNotFound or SocketError.NoData or SocketError.TryAgain => "dns",
            SocketException => "socket",
            AuthenticationException => "tls",
            TimeoutException => "timeout",
            TaskCanceledException => "timeout",
            HttpRequestException => "http",
            _ => "unknown",
        };
        string status = current is HttpRequestException { StatusCode: { } statusCode }
            ? $" status={(int)statusCode}"
            : string.Empty;
        return $"category={category} type={current.GetType().Name} hresult=0x{current.HResult:X8}{status}";
    }

    private async Task<T> RpcSingleAsync<T>(
        string function,
        object body,
        CancellationToken cancellationToken)
    {
        using var request = await CreateRequestAsync(
            HttpMethod.Post,
            $"/rest/v1/rpc/{function}",
            cancellationToken).ConfigureAwait(false);
        request.Headers.TryAddWithoutValidation("Prefer", "return=representation");
        request.Content = JsonContent.Create(body, options: JsonOptions);
        using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        using var document = await ReadDocumentAsync(response, cancellationToken).ConfigureAwait(false);
        var root = document.RootElement;
        var element = root.ValueKind == JsonValueKind.Array
            ? root.GetArrayLength() == 0
                ? throw new InvalidDataException($"RPC {function} returned no rows.")
                : root[0]
            : root;
        return element.Deserialize<T>(JsonOptions)
            ?? throw new InvalidDataException($"RPC {function} returned an invalid row.");
    }

    private async Task RpcNoResultAsync(
        string function,
        object body,
        CancellationToken cancellationToken)
    {
        using var request = await CreateRequestAsync(
            HttpMethod.Post,
            $"/rest/v1/rpc/{function}",
            cancellationToken).ConfigureAwait(false);
        request.Content = JsonContent.Create(body, options: JsonOptions);
        using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException(
                $"Supabase RPC {function} failed with HTTP {(int)response.StatusCode}.",
                inner: null,
                response.StatusCode);
        }
    }

    private Task BroadcastRoomEventAsync(
        Guid roomId,
        string eventName,
        Guid? eventId,
        CancellationToken cancellationToken)
    {
        if (!_roomEpochs.TryGetValue(roomId, out var realtimeEpoch))
        {
            throw new InvalidOperationException(I18n.Get("backend.realtimeEpochMissing"));
        }

        return RpcNoResultAsync(
            "broadcast_room_event",
            new
            {
                p_room_id = roomId,
                p_realtime_epoch = realtimeEpoch,
                p_event = eventName,
                p_event_id = eventId,
            },
            cancellationToken);
    }

    private async Task<HttpRequestMessage> CreateRequestAsync(
        HttpMethod method,
        string relativePath,
        CancellationToken cancellationToken)
    {
        var session = await RequiredSessionAsync(cancellationToken).ConfigureAwait(false);
        var request = new HttpRequestMessage(method, new Uri(_configuration.Url, relativePath));
        request.Headers.Add("apikey", _configuration.PublishableKey);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", session.AccessToken);
        return request;
    }

    private async ValueTask<StoredSupabaseSession> RequiredSessionAsync(
        CancellationToken cancellationToken) =>
        await _sessions.GetStoredSessionAsync(cancellationToken).ConfigureAwait(false)
        ?? throw new InvalidOperationException(I18n.Get("auth.sessionMissing"));

    private static async Task<T> ReadRequiredAsync<T>(
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException(
                $"Supabase REST request failed with HTTP {(int)response.StatusCode}.",
                inner: null,
                response.StatusCode);
        }

        return await response.Content.ReadFromJsonAsync<T>(JsonOptions, cancellationToken)
            .ConfigureAwait(false)
            ?? throw new InvalidDataException("Supabase REST response was empty.");
    }

    private static async Task<JsonDocument> ReadDocumentAsync(
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException(
                $"Supabase RPC failed with HTTP {(int)response.StatusCode}.",
                inner: null,
                response.StatusCode);
        }

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken)
            .ConfigureAwait(false);
        return await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken)
            .ConfigureAwait(false);
    }

    private static ChatMessage MapMessage(DatabaseMessage row) => new(
        row.Id,
        row.RoomId,
        row.SenderId,
        row.Body,
        PostgresTimestampParser.Parse(row.CreatedAt));

    private static void ValidateRoomName(string name)
    {
        if (!RoomNameValidator.IsValid(name))
        {
            throw new ArgumentException(I18n.Get("validation.roomNameLength"), nameof(name));
        }
    }

    private sealed record DatabaseProfile(
        Guid Id,
        string Nickname,
        [property: JsonPropertyName("character_id")] string CharacterId);

    private sealed record DatabaseCommerceEntitlement(
        [property: JsonPropertyName("entitlement_key")] string EntitlementKey,
        string Status);

    private sealed record DatabaseRoom(
        Guid Id,
        string Name,
        [property: JsonPropertyName("owner_id")] Guid OwnerId,
        [property: JsonPropertyName("invite_code_hint")] string InviteCodeHint,
        [property: JsonPropertyName("invite_code_ready")] bool InviteCodeReady,
        [property: JsonPropertyName("realtime_epoch")] long RealtimeEpoch);

    private sealed record DatabaseMembership(
        [property: JsonPropertyName("room_id")] Guid RoomId,
        [property: JsonPropertyName("user_id")] Guid UserId);

    private sealed record DatabaseMessage(
        Guid Id,
        [property: JsonPropertyName("room_id")] Guid RoomId,
        [property: JsonPropertyName("sender_id")] Guid SenderId,
        string Body,
        [property: JsonPropertyName("created_at")] string CreatedAt);

    private sealed record CreateRoomRow(
        [property: JsonPropertyName("room_id")] Guid RoomId,
        [property: JsonPropertyName("invite_code")] string InviteCode);

    private sealed record JoinRoomRow(
        [property: JsonPropertyName("room_id")] Guid? RoomId,
        [property: JsonPropertyName("error_code")] string? ErrorCode);
}
