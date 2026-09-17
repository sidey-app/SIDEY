using System.Globalization;
using System.Runtime.CompilerServices;
using System.Text.Json;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Core.Localization;

namespace Sidey.Infrastructure.Backend;

public sealed class SpringBackendGateway : IBackendGateway, IAsyncDisposable
{
    private static readonly JsonSerializerOptions s_jsonOptions = new(JsonSerializerDefaults.Web);
    private readonly SideyRuntimeConfiguration _configuration;
    private readonly SideyAuthService _auth;
    private readonly ICredentialStore _credentials;
    private readonly SpringRealtimeTransport _transport;
    private readonly RealtimeEventQueue _events = new();
    private readonly CancellationTokenSource _lifetime = new();
    private readonly SemaphoreSlim _recoveryGate = new(1, 1);
    private readonly object _state = new();
    private readonly Dictionary<Guid, SpringMessageLedger> _ledgers = [];
    private readonly HashSet<Guid> _subscriptions = [];
    private readonly HashSet<Guid> _authorizedRooms = [];
    private readonly Dictionary<(Guid Room, Guid User), CancellationTokenSource> _typing = [];
    private readonly Task _reader;
    private Task? _retry;
    private Guid? _activeRoomId;
    private Guid? _userId;
    private PresenceState _activity = PresenceState.Online;
    private bool _connected;
    private bool _resetConnection;
    private bool _paused;
    private bool _disposed;
    private long _revision;
    private long _membershipRevision;
    private long _completedRevision = -1;

    public SpringBackendGateway(SideyRuntimeConfiguration configuration, SideyAuthService auth,
        ICredentialStore credentials, SpringRealtimeTransport? transport = null)
    {
        _configuration = configuration;
        _auth = auth;
        _credentials = credentials;
        _transport = transport ?? new SpringRealtimeTransport();
        _reader = ReadTransportAsync(_lifetime.Token);
    }

    public bool IsRealtimeRecoveryPaused { get { lock (_state) { return _paused; } } }

    public async Task<BackendSnapshot> FetchSnapshotAsync(CancellationToken cancellationToken = default)
    {
        long membershipRevision;
        lock (_state)
        { membershipRevision = _membershipRevision; }
        SideySession session = await _auth.GetSessionAsync(cancellationToken).ConfigureAwait(false);
        lock (_state)
        { _userId = session.UserId; }
        Profile? profile;
        try
        { profile = await ReadAsync<Profile>(HttpMethod.Get, "profile", null, cancellationToken).ConfigureAwait(false); }
        catch (SideyApiException error) when (error.Code == "profile_missing") { profile = null; }
        SpringRoom[] rooms = await ReadAsync<SpringRoom[]>(HttpMethod.Get, "rooms", null, cancellationToken).ConfigureAwait(false);
        SpringEntitlement[] entitlements = await ReadAsync<SpringEntitlement[]>(HttpMethod.Get, "commerce/entitlements", null, cancellationToken).ConfigureAwait(false);
        return new BackendSnapshot(profile, [.. rooms.Select(room => room.Domain)], session.UserId,
            entitlements.Where(value => value.Status == "active").Select(value => value.EntitlementKey).ToHashSet(StringComparer.Ordinal))
        { MembershipRevision = membershipRevision };
    }

    public async Task<Profile> SaveProfileAsync(string nickname, string characterId, CancellationToken cancellationToken = default)
    {
        if (!ProfileValidator.IsValidNickname(nickname))
        {
            throw new ArgumentException(I18n.Get("validation.nicknameLength"), nameof(nickname));
        }
        if (!PixelCharacterCatalog.All.Any(character => character.Id == characterId
            || character.CompatibleAliases.Contains(characterId, StringComparer.Ordinal)))
        {
            throw new ArgumentException("A known character selection is required.", nameof(characterId));
        }
        return await ReadAsync<Profile>(HttpMethod.Put, "profile", new
        {
            nickname = ProfileValidator.NormalizeNickname(nickname),
            characterId = PixelCharacterCatalog.NormalizeId(characterId),
        }, cancellationToken).ConfigureAwait(false);
    }

    public Task<Profile> SetTreeMovementPausedAsync(bool paused, long expectedRevision, CancellationToken cancellationToken = default)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(expectedRevision);
        return ReadAsync<Profile>(HttpMethod.Put, "profile/tree", new { paused, expectedRevision }, cancellationToken);
    }

    public Task<Profile> SetEquippedCosmeticAsync(CommerceProductKind kind, string? catalogItemId, CancellationToken cancellationToken = default)
    {
        if (kind == CommerceProductKind.Character)
        { throw new ArgumentOutOfRangeException(nameof(kind)); }
        return ReadAsync<Profile>(HttpMethod.Put, "profile/equipment",
            new { kind = kind.ToString().ToLowerInvariant(), catalogItemId }, cancellationToken);
    }

    public async Task<CreateRoomResult> CreateRoomAsync(string name, CancellationToken cancellationToken = default)
    {
        SpringCreatedRoom result = await ReadAsync<SpringCreatedRoom>(HttpMethod.Post, "rooms",
            new { name = RoomNameValidator.Normalize(name) }, cancellationToken).ConfigureAwait(false);
        await _credentials.WriteInviteCodeAsync(result.Room.Id, result.InviteCode, cancellationToken).ConfigureAwait(false);
        return new CreateRoomResult(result.Room.Domain, result.InviteCode);
    }

    public async Task<Room> JoinRoomAsync(string inviteCode, CancellationToken cancellationToken = default)
    {
        string normalized = inviteCode.Trim().ToUpperInvariant();
        SpringRoom result = await ReadAsync<SpringRoom>(HttpMethod.Post, "rooms/join",
            new { inviteCode = normalized }, cancellationToken).ConfigureAwait(false);
        await _credentials.WriteInviteCodeAsync(result.Id, normalized, cancellationToken).ConfigureAwait(false);
        return result.Domain;
    }

    public async Task LeaveRoomAsync(Guid roomId, CancellationToken cancellationToken = default)
    {
        await MutateAsync(HttpMethod.Post, $"rooms/{roomId:D}/leave", null, cancellationToken).ConfigureAwait(false);
        await _credentials.DeleteInviteCodeAsync(roomId, cancellationToken).ConfigureAwait(false);
    }

    public Task RenameRoomAsync(Guid roomId, string name, CancellationToken cancellationToken = default)
    {
        return MutateAsync(HttpMethod.Put, $"rooms/{roomId:D}", new { name = RoomNameValidator.Normalize(name) }, cancellationToken);
    }

    public async Task<string> RotateInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default)
    {
        SpringCreatedRoom result = await ReadAsync<SpringCreatedRoom>(HttpMethod.Post,
            $"rooms/{roomId:D}/invite/rotate", null, cancellationToken).ConfigureAwait(false);
        await _credentials.WriteInviteCodeAsync(roomId, result.InviteCode, cancellationToken).ConfigureAwait(false);
        return result.InviteCode;
    }

    public Task RemoveRoomMemberAsync(Guid roomId, Guid userId, CancellationToken cancellationToken = default)
    {
        return MutateAsync(HttpMethod.Delete, $"rooms/{roomId:D}/members/{userId:D}", null, cancellationToken);
    }

    public async Task DeleteRoomAsync(Guid roomId, CancellationToken cancellationToken = default)
    {
        await MutateAsync(HttpMethod.Delete, $"rooms/{roomId:D}", null, cancellationToken).ConfigureAwait(false);
        await _credentials.DeleteInviteCodeAsync(roomId, cancellationToken).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<CommerceProductState>> GetWindowsCommerceStateAsync(CancellationToken cancellationToken = default)
    {
        SpringCatalogProduct[] catalog = await ReadAsync<SpringCatalogProduct[]>(HttpMethod.Get, "commerce/catalog", null, cancellationToken).ConfigureAwait(false);
        SpringEntitlement[] owned = await ReadAsync<SpringEntitlement[]>(HttpMethod.Get, "commerce/entitlements", null, cancellationToken).ConfigureAwait(false);
        var result = new List<CommerceProductState>();
        foreach (CommerceProduct product in WindowsCommerceCatalog.Products)
        {
            SpringCatalogProduct? remote = catalog.SingleOrDefault(value => value.Id == product.Id);
            string? status = owned.FirstOrDefault(value => value.EntitlementKey == product.EntitlementKey)?.Status;
            if (remote is null)
            {
                // Catalog availability is separate from the grant-backed ownership projection.
                // Refunded items missing from the catalog cannot offer a repurchase action.
                result.Add(new CommerceProductState(product, true, status == "active"
                    ? CommercePurchaseState.Owned : CommercePurchaseState.Unavailable));
                continue;
            }
            if (remote.CatalogItemId != product.EffectiveCatalogItemId || remote.EntitlementKey != product.EntitlementKey
                || remote.ProductKind != product.Kind.ToString().ToLowerInvariant() || remote.Currency != "KRW")
            {
                throw new InvalidDataException("Windows commerce product mapping differs from the server.");
            }
            CommercePurchaseState state = status == "active" ? CommercePurchaseState.Owned
                : status == "refunded" ? CommercePurchaseState.Refunded : CommercePurchaseState.Available;
            result.Add(new CommerceProductState(product with { AmountKrw = remote.AmountKrw }, true, state));
        }
        return result;
    }

    public async Task<CommerceCheckout> CreateWindowsCommerceOrderAsync(string productId, CancellationToken cancellationToken = default)
    {
        SpringCheckout checkout = await ReadAsync<SpringCheckout>(HttpMethod.Post, "commerce/orders", new { productId }, cancellationToken).ConfigureAwait(false);
        if (checkout.CheckoutUrl.Scheme != Uri.UriSchemeHttps && !checkout.CheckoutUrl.IsLoopback)
        {
            throw new InvalidDataException("Commerce checkout URL is invalid.");
        }
        return new CommerceCheckout(checkout.OrderId, checkout.CheckoutUrl);
    }

    public async Task<ChatMessage> SendMessageAsync(Guid id, Guid roomId, string body, CancellationToken cancellationToken = default)
    {
        string normalized = MessageValidator.Normalize(body);
        if (!MessageValidator.IsValid(normalized))
        { throw new ArgumentException(I18n.Get("validation.messageLength"), nameof(body)); }
        SideySession session = await _auth.GetSessionAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            JsonElement reply = await CommandAsync(new { type = "message.send", id, roomId, body = normalized }, cancellationToken).ConfigureAwait(false);
            ChatMessage canonical = Decode<SpringMessageAck>(reply).Message;
            Merge(canonical, live: true);
            return canonical;
        }
        catch (Exception error) when (error is not OperationCanceledException
            && error is not SpringRealtimeException { Code: "message_id_conflict" })
        {
            // COMMIT may precede a lost ACK. Lookup never inserts or authorizes a
            // different sender. The outbox preserves this UUID for logical retry.
            ChatMessage? canonical = await FindMessageAsync(id, roomId, cancellationToken).ConfigureAwait(false);
            if (canonical is not null)
            {
                if (canonical.SenderId != session.UserId || canonical.Body != normalized)
                {
                    throw new InvalidOperationException("message_id_conflict");
                }
                Merge(canonical, live: true);
                return canonical;
            }
            throw;
        }
    }

    private async Task<ChatMessage?> FindMessageAsync(Guid id, Guid roomId, CancellationToken cancellationToken)
    {
        try
        { return await ReadAsync<ChatMessage>(HttpMethod.Get, $"rooms/{roomId:D}/messages/{id:D}", null, cancellationToken).ConfigureAwait(false); }
        catch (SideyApiException error) when (error.Code == "message_missing") { return null; }
    }

    public async Task<IReadOnlyList<ChatMessage>> FetchRecentMessagesAsync(Guid roomId, CancellationToken cancellationToken = default)
    {
        lock (_state)
        {
            if (_ledgers.TryGetValue(roomId, out SpringMessageLedger? ledger))
            { return ledger.Messages; }
        }
        MessageHistoryPage page = await FetchMessagePageAsync(roomId, null, 50, cancellationToken).ConfigureAwait(false);
        return [.. page.Messages.Reverse()];
    }

    public Task<MessageHistoryPage> FetchMessagePageAsync(Guid roomId, MessageHistoryCursor? before, int limit = 50, CancellationToken cancellationToken = default)
    {
        before ??= new MessageHistoryCursor(DateTimeOffset.UtcNow.AddDays(1), Guid.Parse("ffffffff-ffff-ffff-ffff-ffffffffffff"));
        return MessagePageAsync(roomId, null, before, null, Math.Clamp(limit, 1, 200), cancellationToken);
    }

    private Task<MessageHistoryPage> MessagePageAsync(Guid roomId, MessageHistoryCursor? after,
        MessageHistoryCursor? before, MessageHistoryCursor? through, int limit, CancellationToken cancellationToken)
    {
        string query = $"rooms/{roomId:D}/messages?limit={limit}";
        foreach ((string Prefix, MessageHistoryCursor? Cursor) pair in new[] { ("after", after), ("before", before), ("through", through) })
        {
            if (pair.Cursor is { } cursor)
            {
                query += $"&{pair.Prefix}CreatedAt={Uri.EscapeDataString(cursor.CreatedAt.ToString("O", CultureInfo.InvariantCulture))}&{pair.Prefix}Id={cursor.Id:D}";
            }
        }
        return ReadAsync<MessageHistoryPage>(HttpMethod.Get, query, null, cancellationToken);
    }

    public async Task SynchronizeRealtimeRoomsAsync(Guid? activeRoomId, PresenceState localPresence,
        CancellationToken cancellationToken = default)
    {
        lock (_state)
        {
            _activeRoomId = activeRoomId;
            _activity = localPresence;
            _revision++;
            _paused = false;
        }
        try
        { await RecoverAsync(cancellationToken).ConfigureAwait(false); }
        catch { RequestRecovery(); throw; }
    }

    private async Task RecoverAsync(CancellationToken cancellationToken)
    {
        await _recoveryGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            while (true)
            {
                long revision;
                bool connect;
                bool reset;
                lock (_state)
                {
                    ObjectDisposedException.ThrowIf(_disposed, this);
                    revision = _revision;
                    reset = _resetConnection;
                    _resetConnection = false;
                    if (reset)
                    { _connected = false; }
                    connect = !_connected || reset;
                }
                Emit(new BackendEvent.ConnectionChanged(RealtimeConnectionStatus.Disconnected));
                if (reset)
                { await _transport.DisconnectAsync().ConfigureAwait(false); }
                // REST verifies session revocation even while the cached access JWT is unexpired.
                BackendSnapshot snapshot = await FetchSnapshotAsync(cancellationToken).ConfigureAwait(false);
                lock (_state)
                { if (revision != _revision || snapshot.MembershipRevision != _membershipRevision) continue; }
                if (connect)
                {
                    SideySession session = await _auth.GetSessionAsync(cancellationToken).ConfigureAwait(false);
                    await _transport.ConnectAsync(_configuration.ApiBaseUrl, session.AccessToken, cancellationToken).ConfigureAwait(false);
                    lock (_state)
                    { _connected = true; _subscriptions.Clear(); }
                }
                HashSet<Guid> rooms = [.. snapshot.Rooms.Select(room => room.Id)];
                lock (_state)
                {
                    if (revision != _revision || snapshot.MembershipRevision != _membershipRevision)
                        continue;
                    UpdateAuthorizedRooms(rooms);
                }
                Guid[] removed;
                lock (_state)
                {
                    if (revision != _revision || snapshot.MembershipRevision != _membershipRevision)
                        continue;
                    removed = [.. _subscriptions.Except(rooms)];
                    foreach (Guid old in _ledgers.Keys.Except(rooms).ToArray())
                    { _ledgers.Remove(old); }
                    if (_activeRoomId is not { } active || !rooms.Contains(active))
                    { _activeRoomId = snapshot.Rooms.FirstOrDefault()?.Id; }
                }
                foreach (Guid room in removed)
                {
                    await CommandAsync(new { type = "unsubscribe", roomId = room }, cancellationToken).ConfigureAwait(false);
                    lock (_state)
                    { _subscriptions.Remove(room); }
                }
                foreach (Room room in snapshot.Rooms)
                {
                    // Server registers live recipients BEFORE taking its checkpoint.
                    // The reader merges live UUIDs during every REST page await.
                    JsonElement reply = await CommandAsync(new { type = "subscribe", roomId = room.Id }, cancellationToken).ConfigureAwait(false);
                    MessageHistoryCursor? through = Decode<SpringSubscribeAck>(reply).RecoveryThrough;
                    MessageHistoryCursor? after;
                    lock (_state)
                    {
                        if (revision != _revision || !_authorizedRooms.Contains(room.Id))
                            break;
                        _subscriptions.Add(room.Id);
                        SpringMessageLedger ledger = Ledger(room.Id);
                        ledger.Prune(DateTimeOffset.UtcNow);
                        after = ledger.ConfirmedCursor;
                    }
                    if (through is not null)
                    {
                        do
                        {
                            MessageHistoryPage page = await MessagePageAsync(room.Id, after, null, through, 200, cancellationToken).ConfigureAwait(false);
                            lock (_state)
                            { if (revision != _revision || !_authorizedRooms.Contains(room.Id)) break; }
                            foreach (ChatMessage message in page.Messages)
                            { Merge(message, live: false); }
                            after = page.NextCursor;
                        } while (after is not null);
                        lock (_state)
                        { if (revision != _revision || !_authorizedRooms.Contains(room.Id)) break; Ledger(room.Id).CompleteRecovery(through); }
                    }
                    IReadOnlyList<ChatMessage> messages;
                    lock (_state)
                    {
                        if (revision != _revision || !_authorizedRooms.Contains(room.Id))
                            break;
                        messages = Ledger(room.Id).Messages;
                        Emit(new BackendEvent.MessagesReplaced(room.Id, messages));
                    }
                    await _transport.SendAsync(new { type = "presence.snapshot", roomId = room.Id }, cancellationToken).ConfigureAwait(false);
                }
                await SendPresenceAsync(cancellationToken).ConfigureAwait(false);
                bool ready;
                lock (_state)
                {
                    ready = _connected && revision == _revision;
                    if (ready)
                    {
                        _completedRevision = revision;
                        Emit(new BackendEvent.SnapshotReceived(snapshot));
                        Emit(new BackendEvent.ConnectionChanged(new RealtimeConnectionStatus(true, true, true)));
                    }
                }
                if (ready)
                {
                    return;
                }
                cancellationToken.ThrowIfCancellationRequested();
            }
        }
        finally { _recoveryGate.Release(); }
    }

    public Task PublishPresenceAsync(Guid roomId, PresenceState state, CancellationToken cancellationToken = default)
    {
        lock (_state)
        {
            // The coordinator publishes only the focused room's OS activity.
            // Room/offline aggregation is solely server-owned.
            _activeRoomId = _authorizedRooms.Contains(roomId) ? roomId : null;
            _activity = state == PresenceState.Online ? PresenceState.Online : PresenceState.Away;
        }
        return SendPresenceAsync(cancellationToken);
    }

    private Task SendPresenceAsync(CancellationToken cancellationToken)
    {
        Guid? room;
        string activity;
        lock (_state)
        { room = _activeRoomId; activity = _activity == PresenceState.Online ? "ONLINE" : "AWAY"; }
        return _transport.SendAsync(new { type = "presence.update", activeRoomId = room, activity }, cancellationToken);
    }

    public Task BroadcastTypingAsync(Guid roomId, bool active, bool keepalive, CancellationToken cancellationToken = default)
    {
        return _transport.SendAsync(new { type = "typing", roomId, active }, cancellationToken);
    }
    public Task BroadcastCharacterPulseAsync(Guid roomId, Guid eventId, CancellationToken cancellationToken = default)
    {
        return _transport.SendAsync(new { type = "character.pulse", roomId, eventId }, cancellationToken);
    }
    public Task BroadcastCharacterThrowAsync(Guid roomId, Guid eventId, Guid targetUserId, CancellationToken cancellationToken = default)
    {
        return _transport.SendAsync(new { type = "character.throw", roomId, eventId, targetUserId }, cancellationToken);
    }

    public void RetryRealtimeConnection(bool userInitiated = false)
    {
        lock (_state)
        { _resetConnection = true; _paused = false; }
        RequestRecovery();
    }

    private void RequestRecovery()
    {
        lock (_state)
        {
            if (_disposed || _paused)
            { return; }
            _revision++;
            _retry ??= Task.Run(RetryLoopAsync);
        }
    }

    private async Task RetryLoopAsync()
    {
        int delay = 1;
        while (!_lifetime.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(delay), _lifetime.Token).ConfigureAwait(false);
                await RecoverAsync(_lifetime.Token).ConfigureAwait(false);
                lock (_state)
                {
                    if (_completedRevision == _revision)
                    { _retry = null; return; }
                }
            }
            catch (AuthenticationRequiredException)
            {
                lock (_state)
                { _paused = true; _connected = false; _retry = null; }
                UpdateAuthorizedRooms([]);
                await _transport.DisconnectAsync().ConfigureAwait(false);
                Emit(new BackendEvent.AuthenticationRequired());
                return;
            }
            catch (OperationCanceledException) when (_lifetime.IsCancellationRequested) { return; }
            catch { delay = Math.Min(delay * 2, 30); }
        }
    }

    private async Task ReadTransportAsync(CancellationToken cancellationToken)
    {
        try
        {
            await foreach (SpringRealtimeEvent value in _transport.ReadEventsAsync(cancellationToken).ConfigureAwait(false))
            {
                if (value is SpringRealtimeEvent.Closed)
                {
                    lock (_state)
                    { _connected = false; }
                    Emit(new BackendEvent.ConnectionChanged(RealtimeConnectionStatus.Disconnected));
                    RequestRecovery();
                }
                else if (value is SpringRealtimeEvent.Frame frame)
                {
                    try
                    { ProcessFrame(frame.Payload); }
                    catch (Exception error) when (error is JsonException or FormatException or InvalidOperationException or KeyNotFoundException or InvalidDataException)
                    {
                        RetryRealtimeConnection();
                    }
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
    }

    private void ProcessFrame(JsonElement payload)
    {
        string? type = payload.GetProperty("type").GetString();
        if (type is "character.pulse" or "character.throw")
        {
            lock (_state)
            {
                if (payload.GetProperty("userId").GetGuid() == _userId)
                { return; }
            }
        }
        if (type == "message.created")
        { Merge(Decode<ChatMessage>(payload.GetProperty("message")), live: true); return; }
        if (type == "room.revoked")
        { RevokeRoom(payload.GetProperty("roomId").GetGuid()); return; }
        if (type == "room.changed")
        { RequestRecovery(); return; }
        if (!payload.TryGetProperty("roomId", out JsonElement roomValue))
        { return; }
        Guid room = roomValue.GetGuid();
        lock (_state)
        { if (!_authorizedRooms.Contains(room)) return; }
        switch (type)
        {
            case "messages.pruned":
                IReadOnlyList<ChatMessage> retained;
                lock (_state)
                { Ledger(room).Prune(DateTimeOffset.UtcNow); retained = Ledger(room).Messages; }
                Emit(new BackendEvent.MessagesReplaced(room, retained));
                break;
            case "presence":
                foreach (JsonProperty member in payload.GetProperty("members").EnumerateObject())
                {
                    PresenceState presence = member.Value.GetString() switch
                    {
                        "ONLINE" => PresenceState.Online,
                        "AWAY" => PresenceState.Away,
                        _ => PresenceState.Offline,
                    };
                    Emit(new BackendEvent.PresenceChanged(room, Guid.Parse(member.Name), presence));
                }
                break;
            case "typing":
                SetTyping(room, payload.GetProperty("userId").GetGuid(), payload.GetProperty("active").GetBoolean());
                break;
            case "character.pulse":
                Emit(new BackendEvent.CharacterPulsed(new CharacterPulseEvent(payload.GetProperty("eventId").GetGuid(), room,
                    payload.GetProperty("userId").GetGuid())));
                break;
            case "character.throw":
                Emit(new BackendEvent.CharacterThrown(new CharacterThrowEvent(payload.GetProperty("eventId").GetGuid(), room,
                    payload.GetProperty("userId").GetGuid(), payload.GetProperty("targetUserId").GetGuid(),
                    payload.GetProperty("sourceCharacterId").GetString()!, payload.TryGetProperty("throwableId", out JsonElement asset) ? asset.GetString() : null)));
                break;
        }
    }

    private void SetTyping(Guid room, Guid user, bool active)
    {
        CancellationTokenSource? previous;
        CancellationTokenSource? current = active ? CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token) : null;
        lock (_state)
        {
            if (user == _userId)
            { current?.Dispose(); return; }
            _typing.Remove((room, user), out previous);
            if (current is not null)
            { _typing[(room, user)] = current; }
        }
        try
        { previous?.Cancel(); }
        catch (ObjectDisposedException) { /* Expiration won the race with replacement. */ }
        Emit(new BackendEvent.TypingChanged(room, user, active));
        if (current is not null)
        { _ = ExpireTypingAsync(room, user, current); }
    }

    private async Task ExpireTypingAsync(Guid room, Guid user, CancellationTokenSource lease)
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(4), lease.Token).ConfigureAwait(false);
            lock (_state)
            {
                if (!_typing.TryGetValue((room, user), out CancellationTokenSource? current) || current != lease)
                { return; }
                _typing.Remove((room, user));
            }
            Emit(new BackendEvent.TypingChanged(room, user, false));
        }
        catch (OperationCanceledException) { }
        finally { lease.Dispose(); }
    }

    private SpringMessageLedger Ledger(Guid room)
    {
        if (!_ledgers.TryGetValue(room, out SpringMessageLedger? ledger))
        { _ledgers[room] = ledger = new SpringMessageLedger(); }
        return ledger;
    }

    private void Merge(ChatMessage message, bool live)
    {
        bool added;
        lock (_state)
        {
            if (!_authorizedRooms.Contains(message.RoomId))
                return;
            added = Ledger(message.RoomId).Merge(message);
            if (live && added)
            { Emit(new BackendEvent.MessageReceived(message)); }
        }
    }

    private void Emit(BackendEvent value)
    {
        // The bounded queue records overflow. Recover only after its consumer
        // resumes and flushes the invalid window, avoiding a REST retry storm.
        _ = _events.TryWrite(value);
    }

    public async IAsyncEnumerable<BackendEvent> SubscribeAsync([EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        await foreach (BackendEvent value in _events.ReadAllAsync(cancellationToken).ConfigureAwait(false))
        {
            if (value is BackendEvent.ReconciliationRequired)
            { RequestRecovery(); continue; }
            lock (_state)
            {
                if (value is BackendEvent.ConnectionChanged { Status.RecoveryReconciled: true } && _completedRevision != _revision)
                    continue;
                if (value is BackendEvent.SnapshotReceived snapshot && snapshot.Snapshot.MembershipRevision < _membershipRevision)
                    continue;
                Guid? room = value switch
                {
                    BackendEvent.MessageReceived message => message.Message.RoomId,
                    BackendEvent.MessagesReplaced messages => messages.RoomId,
                    BackendEvent.PresenceChanged presence => presence.RoomId,
                    BackendEvent.TypingChanged typing => typing.RoomId,
                    BackendEvent.CharacterPulsed pulse => pulse.Pulse.RoomId,
                    BackendEvent.CharacterThrown thrown => thrown.Throw.RoomId,
                    _ => null,
                };
                if (room is { } id && !_authorizedRooms.Contains(id))
                    continue;
            }
            yield return value;
        }
    }

    private Task<JsonElement> CommandAsync(object payload, CancellationToken cancellationToken)
    {
        return _transport.CommandAsync(payload, Guid.NewGuid().ToString("D"), cancellationToken);
    }
    private async Task<T> ReadAsync<T>(HttpMethod method, string path, object? body, CancellationToken cancellationToken)
    {
        try
        { return Decode<T>(await _auth.SendAsync(method, path, body, cancellationToken).ConfigureAwait(false)); }
        catch (SideyApiException error) when (error.Code is "membership_required" or "room_missing")
        { ForgetDeniedRoom(path); throw; }
    }
    private async Task MutateAsync(HttpMethod method, string path, object? body, CancellationToken cancellationToken)
    {
        try
        { _ = await _auth.SendAsync(method, path, body, cancellationToken).ConfigureAwait(false); }
        catch (SideyApiException error) when (error.Code is "membership_required" or "room_missing")
        { ForgetDeniedRoom(path); throw; }
    }

    private void ForgetDeniedRoom(string path)
    {
        string[] segments = path.Split('/');
        if (segments.Length < 2 || segments[0] != "rooms" || !Guid.TryParse(segments[1], out Guid room))
            return;
        RevokeRoom(room);
    }

    private void RevokeRoom(Guid room)
    {
        List<CancellationTokenSource> retired = [];
        lock (_state)
        {
            _membershipRevision++;
            _revision++;
            _authorizedRooms.Remove(room);
            _subscriptions.Remove(room);
            _ledgers.Remove(room);
            if (_activeRoomId == room)
                _activeRoomId = null;
            foreach ((Guid Room, Guid User) key in _typing.Keys.Where(key => key.Room == room).ToArray())
            {
                retired.Add(_typing[key]);
                _typing.Remove(key);
            }
            Emit(new BackendEvent.RoomRevoked(room, _membershipRevision));
        }
        foreach (CancellationTokenSource lease in retired)
        {
            try
            { lease.Cancel(); }
            catch (ObjectDisposedException) { }
        }
        RequestRecovery();
    }

    private void UpdateAuthorizedRooms(HashSet<Guid> rooms)
    {
        List<CancellationTokenSource> retired = [];
        lock (_state)
        {
            _authorizedRooms.Clear();
            _authorizedRooms.UnionWith(rooms);
            foreach (Guid room in _ledgers.Keys.Where(room => !rooms.Contains(room)).ToArray())
                _ledgers.Remove(room);
            foreach ((Guid Room, Guid User) key in _typing.Keys.Where(key => !rooms.Contains(key.Room)).ToArray())
            {
                retired.Add(_typing[key]);
                _typing.Remove(key);
            }
        }
        foreach (CancellationTokenSource lease in retired)
        {
            try
            { lease.Cancel(); }
            catch (ObjectDisposedException) { }
        }
    }

    private static T Decode<T>(JsonElement value)
    {
        return value.Deserialize<T>(s_jsonOptions) ?? throw new InvalidDataException("Invalid SIDEY response.");
    }

    public async ValueTask DisposeAsync()
    {
        Task? retry;
        lock (_state)
        {
            if (_disposed)
            { return; }
            _disposed = true;
            retry = _retry;
        }
        await _lifetime.CancelAsync().ConfigureAwait(false);
        await _transport.DisposeAsync().ConfigureAwait(false);
        try
        { await _reader.ConfigureAwait(false); if (retry is not null) { await retry.ConfigureAwait(false); } }
        catch (OperationCanceledException) { }
        _events.Complete();
        _lifetime.Dispose();
    }
}
