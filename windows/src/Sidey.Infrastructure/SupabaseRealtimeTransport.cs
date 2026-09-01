using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Core.Realtime;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net.WebSockets;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Threading.Channels;

namespace Sidey.Infrastructure;

internal sealed record RealtimePresenceIntent(
    IReadOnlyDictionary<Guid, long> RoomEpochs,
    Guid? ActiveRoomId,
    PresenceState LocalPresence);

internal sealed class SupabaseRealtimeTransport : IAsyncDisposable
{
    private static readonly TimeSpan UnhealthyAfter = TimeSpan.FromSeconds(8);
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private readonly SupabaseRuntimeConfiguration _configuration;
    private readonly IAuthSessionAccessor _sessions;
    private readonly Channel<BackendEvent> _events = Channel.CreateBounded<BackendEvent>(
        new BoundedChannelOptions(256)
        {
            FullMode = BoundedChannelFullMode.Wait,
            SingleReader = true,
            SingleWriter = false,
        });
    private readonly SemaphoreSlim _connectionGate = new(1, 1);
    private readonly SemaphoreSlim _sendGate = new(1, 1);
    private readonly CancellationTokenSource _shutdown = new();
    private readonly CoalescingPublicationQueue<RealtimePresenceIntent> _presenceQueue;
    private readonly ConcurrentDictionary<(Guid RoomId, Guid UserId), CancellationTokenSource> _typingExpiries = [];
    private readonly ConcurrentDictionary<string, TaskCompletionSource<bool>> _pendingReplies = [];
    private IReadOnlyDictionary<Guid, long> _desiredRoomEpochs = new Dictionary<Guid, long>();
    private Guid? _activeRoomId;
    private PresenceState _localPresence = PresenceState.Online;
    private ClientWebSocket? _socket;
    private Task? _receiveTask;
    private Task? _watchdogTask;
    private long _reference;
    private long _connectionGeneration;
    private long _lastReceiveTimestamp = Stopwatch.GetTimestamp();
    private int _recovering;
    private int _overflowed;

    public SupabaseRealtimeTransport(
        SupabaseRuntimeConfiguration configuration,
        IAuthSessionAccessor sessions)
    {
        _configuration = configuration ?? throw new ArgumentNullException(nameof(configuration));
        _sessions = sessions ?? throw new ArgumentNullException(nameof(sessions));
        _presenceQueue = new CoalescingPublicationQueue<RealtimePresenceIntent>(PublishPresenceBatchAsync);
    }

    public async IAsyncEnumerable<BackendEvent> ReadEventsAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        while (await _events.Reader.WaitToReadAsync(cancellationToken).ConfigureAwait(false))
        {
            while (_events.Reader.TryRead(out var backendEvent))
            {
                if (Interlocked.Exchange(ref _overflowed, 0) != 0)
                {
                    while (_events.Reader.TryRead(out _))
                    {
                    }
                    yield return new BackendEvent.ReconciliationRequired();
                    break;
                }
                yield return backendEvent;
            }
        }
    }

    public async Task SynchronizeAsync(
        IReadOnlyDictionary<Guid, long> roomEpochs,
        Guid? activeRoomId,
        PresenceState localPresence,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(roomEpochs);
        await _connectionGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var desired = roomEpochs.ToDictionary(pair => pair.Key, pair => pair.Value);
            var delta = RealtimeEpochSubscriptionPlan.CreateDelta(_desiredRoomEpochs, desired);
            _desiredRoomEpochs = desired;
            _activeRoomId = activeRoomId is { } id && desired.ContainsKey(id) ? id : null;
            _localPresence = localPresence;
            var openedNewSocket = _socket?.State != WebSocketState.Open;
            await EnsureConnectedWithinGateAsync(cancellationToken).ConfigureAwait(false);
            IEnumerable<RealtimeRoomDescriptor> leaves = openedNewSocket
                ? Array.Empty<RealtimeRoomDescriptor>()
                : delta.Leaves;
            foreach (var descriptor in leaves)
            {
                await SendAsync(descriptor.PhoenixTopic, "phx_leave", new { }, cancellationToken)
                    .ConfigureAwait(false);
            }

            IEnumerable<RealtimeRoomDescriptor> joins = openedNewSocket
                ? desired
                    .OrderBy(pair => pair.Key)
                    .SelectMany(pair => RealtimeEpochSubscriptionPlan.Descriptors(
                        pair.Key,
                        pair.Value))
                : delta.Joins;
            foreach (var descriptor in joins)
            {
                await JoinTopicAsync(descriptor, cancellationToken).ConfigureAwait(false);
            }
            if (openedNewSocket)
            {
                Emit(new BackendEvent.ConnectionChanged(true));
            }
        }
        finally
        {
            _connectionGate.Release();
        }

        await _presenceQueue.SubmitAsync(
            new RealtimePresenceIntent(_desiredRoomEpochs, _activeRoomId, _localPresence),
            cancellationToken).ConfigureAwait(false);
    }

    public Task PublishPresenceAsync(
        Guid roomId,
        PresenceState state,
        CancellationToken cancellationToken)
    {
        if (roomId == _activeRoomId)
        {
            _localPresence = state;
        }

        return _presenceQueue.SubmitAsync(
            new RealtimePresenceIntent(_desiredRoomEpochs, _activeRoomId, _localPresence),
            cancellationToken);
    }

    public async ValueTask DisposeAsync()
    {
        _shutdown.Cancel();
        foreach (var expiry in _typingExpiries.Values)
        {
            expiry.Cancel();
            expiry.Dispose();
        }
        _typingExpiries.Clear();
        foreach (var reply in _pendingReplies.Values)
        {
            reply.TrySetCanceled();
        }
        _pendingReplies.Clear();
        await _presenceQueue.DisposeAsync().ConfigureAwait(false);
        var socket = Interlocked.Exchange(ref _socket, null);
        if (socket is not null)
        {
            socket.Abort();
            socket.Dispose();
        }

        if (_receiveTask is not null)
        {
            try
            {
                await _receiveTask.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }
        }

        if (_watchdogTask is not null)
        {
            try
            {
                await _watchdogTask.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }
        }

        _events.Writer.TryComplete();
        _shutdown.Dispose();
        _connectionGate.Dispose();
        _sendGate.Dispose();
    }

    private async Task EnsureConnectedWithinGateAsync(CancellationToken cancellationToken)
    {
        if (_socket?.State == WebSocketState.Open)
        {
            return;
        }

        var session = await _sessions.GetStoredSessionAsync(cancellationToken).ConfigureAwait(false)
            ?? throw new InvalidOperationException("Supabase 세션이 없습니다.");
        var socket = new ClientWebSocket();
        socket.Options.SetRequestHeader("Authorization", $"Bearer {session.AccessToken}");
        socket.Options.SetRequestHeader("apikey", _configuration.PublishableKey);
        var builder = new UriBuilder(_configuration.Url)
        {
            Scheme = "wss",
            Port = -1,
            Path = "/realtime/v1/websocket",
            Query = $"apikey={Uri.EscapeDataString(_configuration.PublishableKey)}&vsn=1.0.0",
        };
        await socket.ConnectAsync(builder.Uri, cancellationToken).ConfigureAwait(false);

        var previous = Interlocked.Exchange(ref _socket, socket);
        previous?.Abort();
        previous?.Dispose();
        var generation = Interlocked.Increment(ref _connectionGeneration);
        Volatile.Write(ref _lastReceiveTimestamp, Stopwatch.GetTimestamp());
        _receiveTask = Task.Run(() => ReceiveLoopAsync(socket, generation), CancellationToken.None);
        _watchdogTask ??= Task.Run(WatchdogLoopAsync, CancellationToken.None);
    }

    private async Task JoinTopicAsync(
        RealtimeRoomDescriptor descriptor,
        CancellationToken cancellationToken)
    {
        var session = await _sessions.GetStoredSessionAsync(cancellationToken).ConfigureAwait(false)
            ?? throw new InvalidOperationException("Supabase 세션이 없습니다.");
        var isEphemeral = descriptor.Kind == RealtimeTopicKind.Ephemeral;
        object config;
        if (isEphemeral)
        {
            config = new
            {
                broadcast = new { ack = false, self = false },
                presence = new { key = session.UserId.ToString("D") },
                postgres_changes = Array.Empty<object>(),
                @private = true,
            };
        }
        else
        {
            config = new
            {
                broadcast = new { ack = false, self = false },
                postgres_changes = Array.Empty<object>(),
                @private = true,
            };
        }
        var reply = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var reference = await SendAsync(
            descriptor.PhoenixTopic,
            "phx_join",
            new
            {
                config,
                access_token = session.AccessToken,
            },
            cancellationToken,
            reply).ConfigureAwait(false);
        try
        {
            await reply.Task.WaitAsync(TimeSpan.FromSeconds(5), cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _pendingReplies.TryRemove(reference, out _);
        }
    }

    private async Task PublishPresenceBatchAsync(
        RealtimePresenceIntent intent,
        CancellationToken cancellationToken)
    {
        var session = await _sessions.GetStoredSessionAsync(cancellationToken).ConfigureAwait(false)
            ?? throw new InvalidOperationException("Supabase 세션이 없습니다.");
        foreach (var room in intent.RoomEpochs.OrderBy(pair => pair.Key))
        {
            var state = PresencePublicationPlan.StateFor(
                room.Key,
                intent.ActiveRoomId,
                intent.LocalPresence);
            var topic = new RealtimeRoomDescriptor(
                room.Key,
                room.Value,
                RealtimeTopicKind.Ephemeral);
            await SendAsync(
                topic.PhoenixTopic,
                "presence",
                new
                {
                    type = "presence",
                    @event = "track",
                    payload = new
                    {
                        user_id = session.UserId,
                        state = state.ToString().ToLowerInvariant(),
                        online_at = DateTimeOffset.UtcNow.ToString("O"),
                    },
                },
                cancellationToken).ConfigureAwait(false);
        }
    }

    private async Task<string> SendAsync(
        string topic,
        string eventName,
        object payload,
        CancellationToken cancellationToken,
        TaskCompletionSource<bool>? reply = null)
    {
        var socket = _socket;
        if (socket?.State != WebSocketState.Open)
        {
            throw new InvalidOperationException("Supabase Realtime 연결을 사용할 수 없습니다.");
        }

        var reference = Interlocked.Increment(ref _reference).ToString();
        var bytes = JsonSerializer.SerializeToUtf8Bytes(
            new
            {
                topic,
                @event = eventName,
                payload,
                @ref = reference,
            },
            JsonOptions);
        if (reply is not null && !_pendingReplies.TryAdd(reference, reply))
        {
            throw new InvalidOperationException("Supabase Realtime reference collision.");
        }
        await _sendGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await socket.SendAsync(
                bytes,
                WebSocketMessageType.Text,
                endOfMessage: true,
                cancellationToken).ConfigureAwait(false);
        }
        catch
        {
            if (reply is not null)
            {
                _pendingReplies.TryRemove(reference, out _);
            }
            throw;
        }
        finally
        {
            _sendGate.Release();
        }
        return reference;
    }

    private async Task ReceiveLoopAsync(ClientWebSocket socket, long generation)
    {
        var buffer = new byte[64 * 1024];
        try
        {
            while (!_shutdown.IsCancellationRequested && socket.State == WebSocketState.Open)
            {
                var count = 0;
                ValueWebSocketReceiveResult result;
                do
                {
                    result = await socket.ReceiveAsync(
                        buffer.AsMemory(count),
                        _shutdown.Token).ConfigureAwait(false);
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        throw new WebSocketException("Supabase Realtime closed the connection.");
                    }

                    count += result.Count;
                    if (count == buffer.Length && !result.EndOfMessage)
                    {
                        throw new InvalidDataException("Supabase Realtime message exceeded 64 KiB.");
                    }
                }
                while (!result.EndOfMessage);

                Volatile.Write(ref _lastReceiveTimestamp, Stopwatch.GetTimestamp());
                HandleMessage(buffer.AsMemory(0, count));
            }
        }
        catch (OperationCanceledException) when (_shutdown.IsCancellationRequested)
        {
            return;
        }
        catch (Exception)
        {
            if (generation != Volatile.Read(ref _connectionGeneration) || _shutdown.IsCancellationRequested)
            {
                return;
            }

            Emit(new BackendEvent.ConnectionChanged(false));
            _ = RecoverAsync();
        }
    }

    private async Task WatchdogLoopAsync()
    {
        using var timer = new PeriodicTimer(RealtimeRecoveryPolicy.WatchdogInterval);
        while (await timer.WaitForNextTickAsync(_shutdown.Token).ConfigureAwait(false))
        {
            var socket = _socket;
            if (socket?.State != WebSocketState.Open)
            {
                Emit(new BackendEvent.ConnectionChanged(false));
                _ = RecoverAsync();
                continue;
            }

            var silence = Stopwatch.GetElapsedTime(Volatile.Read(ref _lastReceiveTimestamp));
            if (silence >= UnhealthyAfter)
            {
                socket.Abort();
                Emit(new BackendEvent.ConnectionChanged(false));
                _ = RecoverAsync();
                continue;
            }

            try
            {
                await SendAsync("phoenix", "heartbeat", new { }, _shutdown.Token)
                    .ConfigureAwait(false);
            }
            catch
            {
                socket.Abort();
            }
        }
    }

    private async Task RecoverAsync()
    {
        if (Interlocked.Exchange(ref _recovering, 1) != 0)
        {
            return;
        }

        try
        {
            for (var attempt = 1; !_shutdown.IsCancellationRequested; attempt++)
            {
                await Task.Delay(
                    RealtimeRecoveryPolicy.DelayForAttempt(attempt),
                    _shutdown.Token).ConfigureAwait(false);
                await _connectionGate.WaitAsync(_shutdown.Token).ConfigureAwait(false);
                try
                {
                    var existing = Interlocked.Exchange(ref _socket, null);
                    existing?.Abort();
                    existing?.Dispose();
                    await EnsureConnectedWithinGateAsync(_shutdown.Token).ConfigureAwait(false);
                    foreach (var room in _desiredRoomEpochs.OrderBy(pair => pair.Key))
                    {
                        foreach (var descriptor in RealtimeEpochSubscriptionPlan.Descriptors(
                            room.Key,
                            room.Value))
                        {
                            await JoinTopicAsync(descriptor, _shutdown.Token).ConfigureAwait(false);
                        }
                    }
                }
                catch when (!_shutdown.IsCancellationRequested)
                {
                    continue;
                }
                finally
                {
                    _connectionGate.Release();
                }

                try
                {
                    await _presenceQueue.SubmitAsync(
                        new RealtimePresenceIntent(
                            _desiredRoomEpochs,
                            _activeRoomId,
                            _localPresence),
                        _shutdown.Token).ConfigureAwait(false);
                }
                catch when (!_shutdown.IsCancellationRequested)
                {
                    Emit(new BackendEvent.ConnectionChanged(false));
                    continue;
                }
                Emit(new BackendEvent.ConnectionChanged(true));
                return;
            }
        }
        catch (OperationCanceledException) when (_shutdown.IsCancellationRequested)
        {
        }
        finally
        {
            Interlocked.Exchange(ref _recovering, 0);
        }
    }

    private void HandleMessage(ReadOnlyMemory<byte> utf8)
    {
        using var document = JsonDocument.Parse(utf8);
        var root = document.RootElement;
        if (root.TryGetProperty("event", out var replyEvent)
            && replyEvent.GetString() == "phx_reply"
            && root.TryGetProperty("ref", out var replyReference)
            && replyReference.GetString() is { } reference
            && _pendingReplies.TryRemove(reference, out var completion))
        {
            var succeeded = root.TryGetProperty("payload", out var replyPayload)
                && replyPayload.TryGetProperty("status", out var status)
                && status.GetString() == "ok";
            if (succeeded)
            {
                completion.TrySetResult(true);
            }
            else
            {
                completion.TrySetException(
                    new InvalidOperationException("Supabase Realtime subscription was rejected."));
            }
            return;
        }

        if (!root.TryGetProperty("topic", out var topicElement)
            || !RealtimeRoomDescriptor.TryParsePhoenixTopic(
                topicElement.GetString(),
                out var descriptor)
            || !_desiredRoomEpochs.TryGetValue(descriptor.RoomId, out var expectedEpoch)
            || expectedEpoch != descriptor.Epoch
            || !root.TryGetProperty("event", out var eventElement))
        {
            return;
        }

        var eventName = eventElement.GetString();
        var payload = root.TryGetProperty("payload", out var value) ? value : default;
        if (eventName == "presence_diff" && descriptor.Kind == RealtimeTopicKind.Ephemeral)
        {
            HandlePresence(descriptor.RoomId, payload);
            return;
        }
        if (eventName == "presence_state" && descriptor.Kind == RealtimeTopicKind.Ephemeral)
        {
            HandlePresenceState(descriptor.RoomId, payload);
            return;
        }

        if (eventName != "broadcast" || payload.ValueKind != JsonValueKind.Object)
        {
            return;
        }

        var broadcastEvent = payload.TryGetProperty("event", out var broadcastEventElement)
            ? broadcastEventElement.GetString()
            : null;
        var inner = payload.TryGetProperty("payload", out var innerPayload) ? innerPayload : payload;
        if (!TryGuid(inner, "room_id", out var payloadRoomId)
            || payloadRoomId != descriptor.RoomId)
        {
            return;
        }

        if (descriptor.Kind == RealtimeTopicKind.Database)
        {
            HandleDatabaseBroadcast(descriptor.RoomId, broadcastEvent, inner);
            return;
        }

        switch (broadcastEvent)
        {
            case "typing_start":
                HandleTyping(descriptor.RoomId, inner, active: true);
                break;
            case "typing_stop":
                HandleTyping(descriptor.RoomId, inner, active: false);
                break;
            case "character_pulse":
                if (TryGuid(inner, "user_id", out var pulseUserId)
                    && TryGuid(inner, "event_id", out var pulseId))
                {
                    Emit(new BackendEvent.CharacterPulsed(
                        new CharacterPulseEvent(pulseId, descriptor.RoomId, pulseUserId)));
                }
                break;
        }
    }

    private void HandleDatabaseBroadcast(
        Guid roomId,
        string? eventName,
        JsonElement payload)
    {
        switch (eventName)
        {
            case "message_changed":
                var hasOperation = payload.TryGetProperty("operation", out var operationElement);
                var operation = hasOperation ? operationElement.GetString() : null;
                if (TryGuid(payload, "message_id", out var messageId)
                    && operation is "INSERT" or "UPDATE" or "DELETE")
                {
                    Emit(new BackendEvent.MessageChanged(
                        roomId,
                        messageId,
                        operation));
                }
                break;
            case "messages_pruned":
                Emit(new BackendEvent.MessagesInvalidated(roomId));
                break;
            case "structure_changed":
                if (payload.TryGetProperty("entity", out var entity)
                    && entity.GetString() is "profiles" or "rooms" or "room_members"
                    && payload.TryGetProperty("operation", out var structuralOperation)
                    && structuralOperation.GetString() is "INSERT" or "UPDATE" or "DELETE")
                {
                    Emit(new BackendEvent.RoomStructureChanged(roomId));
                }
                break;
        }
    }

    private void HandlePresence(Guid roomId, JsonElement payload)
    {
        if (payload.ValueKind != JsonValueKind.Object)
        {
            return;
        }

        var joined = new Dictionary<Guid, PresenceState>();
        if (payload.TryGetProperty("joins", out var joins) && joins.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in joins.EnumerateObject())
            {
                if (!Guid.TryParse(property.Name, out var userId))
                {
                    continue;
                }

                joined[userId] = ParsePresenceState(property.Value);
            }
        }

        var left = new HashSet<Guid>();
        if (payload.TryGetProperty("leaves", out var leaves) && leaves.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in leaves.EnumerateObject())
            {
                if (Guid.TryParse(property.Name, out var userId))
                {
                    left.Add(userId);
                }
            }
        }

        foreach (var update in PresenceChangePlan.Updates(joined, left))
        {
            Emit(new BackendEvent.PresenceChanged(
                roomId,
                update.UserId,
                update.State));
        }
    }

    private void HandlePresenceState(Guid roomId, JsonElement payload)
    {
        if (payload.ValueKind != JsonValueKind.Object)
        {
            return;
        }

        foreach (var property in payload.EnumerateObject())
        {
            if (Guid.TryParse(property.Name, out var userId))
            {
                Emit(new BackendEvent.PresenceChanged(
                    roomId,
                    userId,
                    ParsePresenceState(property.Value)));
            }
        }
    }

    private static PresenceState ParsePresenceState(JsonElement value)
    {
        if (value.TryGetProperty("metas", out var metas)
            && metas.ValueKind == JsonValueKind.Array
            && metas.GetArrayLength() > 0)
        {
            value = metas[0];
        }

        return value.TryGetProperty("state", out var stateElement)
            && Enum.TryParse<PresenceState>(stateElement.GetString(), true, out var parsed)
                ? parsed
                : PresenceState.Online;
    }

    private void HandleTyping(Guid roomId, JsonElement payload, bool active)
    {
        if (!TryGuid(payload, "user_id", out var userId))
        {
            return;
        }

        var key = (roomId, userId);
        if (_typingExpiries.TryRemove(key, out var existing))
        {
            existing.Cancel();
            existing.Dispose();
        }

        Emit(new BackendEvent.TypingChanged(roomId, userId, active));
        if (!active)
        {
            return;
        }

        var expiry = CancellationTokenSource.CreateLinkedTokenSource(_shutdown.Token);
        _typingExpiries[key] = expiry;
        _ = ExpireTypingAsync(key, expiry);
    }

    private async Task ExpireTypingAsync(
        (Guid RoomId, Guid UserId) key,
        CancellationTokenSource expiry)
    {
        try
        {
            await Task.Delay(TypingLease.RemoteExpiry, expiry.Token).ConfigureAwait(false);
            Emit(new BackendEvent.TypingChanged(key.RoomId, key.UserId, false));
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            if (_typingExpiries.TryGetValue(key, out var current) && ReferenceEquals(current, expiry))
            {
                _typingExpiries.TryRemove(key, out _);
                expiry.Dispose();
            }
        }
    }

    private static bool TryGuid(JsonElement element, string name, out Guid value)
    {
        value = default;
        return element.ValueKind == JsonValueKind.Object
            && element.TryGetProperty(name, out var property)
            && Guid.TryParse(property.GetString(), out value);
    }

    private void Emit(BackendEvent backendEvent)
    {
        if (!_events.Writer.TryWrite(backendEvent))
        {
            Interlocked.Exchange(ref _overflowed, 1);
            _ = RecoverAsync();
        }
    }
}
