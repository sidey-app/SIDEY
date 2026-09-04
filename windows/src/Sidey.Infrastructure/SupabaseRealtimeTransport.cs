using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Runtime.CompilerServices;
using System.Security.Authentication;
using System.Text.Json;
using System.Threading.Channels;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Sidey.Core.Realtime;

namespace Sidey.Infrastructure;

internal sealed record RealtimePresenceIntent(
    IReadOnlyDictionary<Guid, long> RoomEpochs,
    Guid? ActiveRoomId,
    PresenceState LocalPresence);

internal sealed class SupabaseRealtimeTransport : IAsyncDisposable
{
    private static readonly TimeSpan UnhealthyAfter = TimeSpan.FromSeconds(30);
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
    private readonly ExpiringLeaseRegistry<(Guid RoomId, Guid UserId)> _typingExpiries;
    private readonly ConcurrentDictionary<string, TaskCompletionSource<bool>> _pendingReplies = [];
    private readonly ConcurrentDictionary<string, string> _joinReferences = [];
    private readonly object _recoveryGate = new();
    private IReadOnlyDictionary<Guid, long> _desiredRoomEpochs = new Dictionary<Guid, long>();
    private Guid? _activeRoomId;
    private PresenceState _localPresence = PresenceState.Online;
    private RealtimeSocketSession? _socketSession;
    private Task? _watchdogTask;
    private Task _recoveryTask = Task.CompletedTask;
    private long _reference;
    private long _connectionGeneration;
    private long _lastReceiveTimestamp = Stopwatch.GetTimestamp();
    private long _lastConnectionHealthTimestamp = Stopwatch.GetTimestamp();
    private RealtimeConnectionStatus _lastEmittedConnectionStatus =
        RealtimeConnectionStatus.Disconnected;
    private int _recovering;
    private int _overflowed;
    private long _overflowCount;

    public SupabaseRealtimeTransport(
        SupabaseRuntimeConfiguration configuration,
        IAuthSessionAccessor sessions)
    {
        _configuration = configuration ?? throw new ArgumentNullException(nameof(configuration));
        _sessions = sessions ?? throw new ArgumentNullException(nameof(sessions));
        _presenceQueue = new CoalescingPublicationQueue<RealtimePresenceIntent>(PublishPresenceBatchAsync);
        _typingExpiries = new ExpiringLeaseRegistry<(Guid RoomId, Guid UserId)>(
            TypingLease.RemoteExpiry,
            key => Emit(new BackendEvent.TypingChanged(key.RoomId, key.UserId, false)));
    }

    internal RealtimeConnectionStatus ConnectionStatus =>
        Volatile.Read(ref _lastEmittedConnectionStatus);

    public async IAsyncEnumerable<BackendEvent> ReadEventsAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        while (await _events.Reader.WaitToReadAsync(cancellationToken).ConfigureAwait(false))
        {
            while (_events.Reader.TryRead(out var backendEvent))
            {
                if (Interlocked.Exchange(ref _overflowed, 0) != 0)
                {
                    long dropped = Interlocked.Exchange(ref _overflowCount, 0);
                    while (_events.Reader.TryRead(out _))
                    {
                        dropped++;
                    }
                    yield return new BackendEvent.Diagnostic(
                        $"realtime-event-queue-overflow capacity=256 dropped={dropped}");
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
            Emit(new BackendEvent.Diagnostic(
                $"realtime-synchronization-started rooms={desired.Count}"));
            var delta = RealtimeEpochSubscriptionPlan.CreateDelta(_desiredRoomEpochs, desired);
            _desiredRoomEpochs = desired;
            _activeRoomId = activeRoomId is { } id && desired.ContainsKey(id) ? id : null;
            _localPresence = localPresence;
            var openedNewSocket = _socketSession?.Socket.State != WebSocketState.Open;
            try
            {
                await EnsureConnectedWithinGateAsync(cancellationToken).ConfigureAwait(false);
            }
            catch (WebSocketException exception) when (!cancellationToken.IsCancellationRequested
                && !_shutdown.IsCancellationRequested)
            {
                Emit(new BackendEvent.TechnicalError(ConnectionFailureMessage(exception)));
                EmitDisconnected();
                ScheduleRecovery();
                return;
            }
            IEnumerable<RealtimeRoomDescriptor> leaves = openedNewSocket
                ? Array.Empty<RealtimeRoomDescriptor>()
                : delta.Leaves;
            foreach (var descriptor in leaves)
            {
                await SendAsync(descriptor.PhoenixTopic, "phx_leave", new { }, cancellationToken)
                    .ConfigureAwait(false);
                _joinReferences.TryRemove(descriptor.PhoenixTopic, out _);
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
            EmitConnectionStatus(CurrentTransportStatus());
            Emit(new BackendEvent.Diagnostic(
                $"realtime-synchronization-completed rooms={desired.Count}"));
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
        foreach (var reply in _pendingReplies.Values)
        {
            reply.TrySetCanceled();
        }
        _pendingReplies.Clear();
        _joinReferences.Clear();
        await _presenceQueue.DisposeAsync().ConfigureAwait(false);
        await _connectionGate.WaitAsync().ConfigureAwait(false);
        try
        {
            await DisconnectSocketWithinGateAsync().ConfigureAwait(false);
        }
        finally
        {
            _connectionGate.Release();
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

        Task recoveryTask;
        lock (_recoveryGate)
        {
            recoveryTask = _recoveryTask;
        }
        await recoveryTask.ConfigureAwait(false);
        await _typingExpiries.DisposeAsync().ConfigureAwait(false);

        _events.Writer.TryComplete();
        _shutdown.Dispose();
        _connectionGate.Dispose();
        _sendGate.Dispose();
    }

    private async Task EnsureConnectedWithinGateAsync(CancellationToken cancellationToken)
    {
        if (_socketSession?.Socket.State == WebSocketState.Open)
        {
            return;
        }

        _ = await _sessions.GetStoredSessionAsync(cancellationToken).ConfigureAwait(false)
            ?? throw new InvalidOperationException(I18n.Get("auth.sessionMissing"));
        var socket = new ClientWebSocket();
        socket.Options.HttpVersion = HttpVersion.Version11;
        socket.Options.HttpVersionPolicy = HttpVersionPolicy.RequestVersionExact;
        var builder = new UriBuilder(_configuration.Url)
        {
            Scheme = "wss",
            Port = -1,
            Path = "/realtime/v1/websocket",
            Query = $"apikey={Uri.EscapeDataString(_configuration.PublishableKey)}&vsn=1.0.0",
        };
        try
        {
            Emit(new BackendEvent.Diagnostic("realtime-websocket-connect-started"));
            await socket.ConnectAsync(builder.Uri, cancellationToken).ConfigureAwait(false);
            Emit(new BackendEvent.Diagnostic("realtime-websocket-connect-completed"));
        }
        catch
        {
            socket.Dispose();
            throw;
        }

        await DisconnectSocketWithinGateAsync().ConfigureAwait(false);
        _joinReferences.Clear();
        var generation = Interlocked.Increment(ref _connectionGeneration);
        Volatile.Write(ref _lastReceiveTimestamp, Stopwatch.GetTimestamp());
        _socketSession = new RealtimeSocketSession(
            socket,
            activeSocket => ReceiveLoopAsync(activeSocket, generation));
        _watchdogTask ??= Task.Run(WatchdogLoopAsync, CancellationToken.None);
    }

    private async Task DisconnectSocketWithinGateAsync()
    {
        RealtimeSocketSession? session = Interlocked.Exchange(ref _socketSession, null);
        Interlocked.Increment(ref _connectionGeneration);
        if (session is not null)
        {
            await session.DisposeAsync().ConfigureAwait(false);
        }
        _joinReferences.Clear();
    }

    private static string ConnectionFailureMessage(Exception exception)
    {
        var current = exception;
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
            WebSocketException => "websocket",
            _ => "unknown",
        };
        string detail = current is SocketException socketException
            ? $" socket={socketException.SocketErrorCode} native={socketException.NativeErrorCode}"
            : current is HttpRequestException { StatusCode: { } statusCode }
                ? $" status={(int)statusCode}"
                : string.Empty;
        return $"Realtime WebSocket connection failed: category={category} type={current.GetType().Name}{detail}";
    }

    private async Task JoinTopicAsync(
        RealtimeRoomDescriptor descriptor,
        CancellationToken cancellationToken)
    {
        var session = await _sessions.GetStoredSessionAsync(cancellationToken).ConfigureAwait(false)
            ?? throw new InvalidOperationException(I18n.Get("auth.sessionMissing"));
        var isEphemeral = descriptor.Kind == RealtimeTopicKind.Ephemeral;
        string topicKind = isEphemeral ? "ephemeral" : "database";
        Emit(new BackendEvent.Diagnostic(
            $"realtime-topic-subscribe-started kind={topicKind}"));
        object config;
        if (isEphemeral)
        {
            config = new
            {
                broadcast = new { ack = false, self = false },
                presence = new
                {
                    key = session.UserId.ToString("D"),
                    enabled = true,
                },
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
        _joinReferences[descriptor.PhoenixTopic] = reference;
        try
        {
            await reply.Task.WaitAsync(TimeSpan.FromSeconds(5), cancellationToken).ConfigureAwait(false);
        }
        catch
        {
            _joinReferences.TryRemove(
                new KeyValuePair<string, string>(descriptor.PhoenixTopic, reference));
            Emit(new BackendEvent.Diagnostic(
                $"realtime-topic-subscribe-failed kind={topicKind}"));
            throw;
        }
        finally
        {
            _pendingReplies.TryRemove(reference, out _);
        }
        Emit(new BackendEvent.Diagnostic(
            $"realtime-topic-subscribe-completed kind={topicKind}"));
    }

    private async Task PublishPresenceBatchAsync(
        RealtimePresenceIntent intent,
        CancellationToken cancellationToken)
    {
        var session = await _sessions.GetStoredSessionAsync(cancellationToken).ConfigureAwait(false)
            ?? throw new InvalidOperationException(I18n.Get("auth.sessionMissing"));
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
        var socket = _socketSession?.Socket;
        if (socket?.State != WebSocketState.Open)
        {
            throw new InvalidOperationException(I18n.Get("backend.realtimeUnavailable"));
        }

        var reference = Interlocked.Increment(ref _reference).ToString();
        var joinReference = eventName == "phx_join"
            ? reference
            : _joinReferences.GetValueOrDefault(topic);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(
            new
            {
                join_ref = joinReference,
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
                        string closeCode = socket.CloseStatus is { } status
                            ? ((int)status).ToString()
                            : "unknown";
                        Emit(new BackendEvent.Diagnostic(
                            $"realtime-websocket-closed code={closeCode}"));
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
        catch (Exception exception)
        {
            if (generation != Volatile.Read(ref _connectionGeneration) || _shutdown.IsCancellationRequested)
            {
                return;
            }

            Emit(new BackendEvent.TechnicalError(ConnectionFailureMessage(exception)));
            EmitDisconnected();
            ScheduleRecovery();
        }
    }

    private async Task WatchdogLoopAsync()
    {
        using var timer = new PeriodicTimer(RealtimeRecoveryPolicy.WatchdogInterval);
        while (await timer.WaitForNextTickAsync(_shutdown.Token).ConfigureAwait(false))
        {
            var socket = _socketSession?.Socket;
            if (socket?.State != WebSocketState.Open)
            {
                EmitDisconnected();
                ScheduleRecovery();
                continue;
            }

            var silence = Stopwatch.GetElapsedTime(Volatile.Read(ref _lastReceiveTimestamp));
            if (silence >= UnhealthyAfter)
            {
                Emit(new BackendEvent.Diagnostic(
                    $"realtime-heartbeat-timeout silence-ms={(long)silence.TotalMilliseconds}"));
                socket.Abort();
                Emit(new BackendEvent.TechnicalError("Realtime WebSocket heartbeat timed out."));
                EmitDisconnected();
                ScheduleRecovery();
                continue;
            }

            if (Stopwatch.GetElapsedTime(_lastConnectionHealthTimestamp) >= TimeSpan.FromMinutes(1))
            {
                _lastConnectionHealthTimestamp = Stopwatch.GetTimestamp();
                Emit(new BackendEvent.Diagnostic(
                    $"realtime-health silence-ms={(long)silence.TotalMilliseconds} "
                    + $"event-queue-size={_events.Reader.Count}"));
            }

            try
            {
                await SendAsync("phoenix", "heartbeat", new { }, _shutdown.Token)
                    .ConfigureAwait(false);
            }
            catch (Exception exception)
            {
                Emit(new BackendEvent.TechnicalError(ConnectionFailureMessage(exception)));
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
                TimeSpan delay = RealtimeRecoveryPolicy.DelayForAttempt(attempt);
                Emit(new BackendEvent.Diagnostic(
                    $"realtime-reconnect-scheduled attempt={attempt} delay-ms={(long)delay.TotalMilliseconds}"));
                await Task.Delay(delay, _shutdown.Token).ConfigureAwait(false);
                Emit(new BackendEvent.Diagnostic(
                    $"realtime-reconnect-started attempt={attempt}"));
                await _connectionGate.WaitAsync(_shutdown.Token).ConfigureAwait(false);
                try
                {
                    await DisconnectSocketWithinGateAsync().ConfigureAwait(false);
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
                catch (Exception exception) when (!_shutdown.IsCancellationRequested)
                {
                    Emit(new BackendEvent.Diagnostic(
                        $"realtime-reconnect-failed attempt={attempt} {ConnectionFailureMessage(exception)}"));
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
                catch (Exception exception) when (!_shutdown.IsCancellationRequested)
                {
                    Emit(new BackendEvent.Diagnostic(
                        $"realtime-reconnect-failed attempt={attempt} stage=presence {ConnectionFailureMessage(exception)}"));
                    EmitDisconnected();
                    continue;
                }
                Emit(new BackendEvent.Diagnostic(
                    $"realtime-reconnect-completed attempt={attempt}"));
                EmitConnectionStatus(CurrentTransportStatus());
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

    private RealtimeConnectionStatus CurrentTransportStatus()
    {
        bool socketConnected = _socketSession?.Socket.State == WebSocketState.Open;
        bool transportConnected = socketConnected
            && _desiredRoomEpochs.All(room => RealtimeEpochSubscriptionPlan
                .Descriptors(room.Key, room.Value)
                .All(descriptor => _joinReferences.ContainsKey(descriptor.PhoenixTopic)));
        bool activeRoomConnected = transportConnected
            && _activeRoomId is { } activeRoomId
            && _desiredRoomEpochs.TryGetValue(activeRoomId, out long epoch)
            && RealtimeEpochSubscriptionPlan.Descriptors(activeRoomId, epoch)
                .All(descriptor => _joinReferences.ContainsKey(descriptor.PhoenixTopic));
        return new RealtimeConnectionStatus(
            transportConnected,
            activeRoomConnected,
            RecoveryReconciled: false);
    }

    private void EmitDisconnected() => EmitConnectionStatus(RealtimeConnectionStatus.Disconnected);

    private void EmitConnectionStatus(RealtimeConnectionStatus status)
    {
        if (status == Volatile.Read(ref _lastEmittedConnectionStatus))
        {
            return;
        }

        Volatile.Write(ref _lastEmittedConnectionStatus, status);
        Emit(new BackendEvent.ConnectionChanged(status));
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
            case "character_throw":
                if (inner.TryGetProperty("schema_version", out var schemaVersion)
                    && schemaVersion.TryGetInt32(out var version)
                    && version == 1
                    && TryGuid(inner, "event_id", out var throwId)
                    && TryGuid(inner, "actor_user_id", out var actorUserId)
                    && TryGuid(inner, "target_user_id", out var targetUserId)
                    && actorUserId != targetUserId
                    && inner.TryGetProperty("source_character_id", out var sourceCharacterElement)
                    && sourceCharacterElement.ValueKind == JsonValueKind.String
                    && sourceCharacterElement.GetString() is { Length: > 0 and <= 40 } sourceCharacterId
                    && IsValidCharacterId(sourceCharacterId))
                {
                    Emit(new BackendEvent.CharacterThrown(new CharacterThrowEvent(
                        throwId,
                        descriptor.RoomId,
                        actorUserId,
                        targetUserId,
                        sourceCharacterId)));
                }
                break;
        }
    }

    private static bool IsValidCharacterId(string value)
    {
        foreach (var character in value)
        {
            if (character != '_'
                && (character < 'a' || character > 'z')
                && (character < '0' || character > '9'))
            {
                return false;
            }
        }
        return true;
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
            return PresenceAggregatePlan.MostAvailable(
                metas.EnumerateArray().Select(ParsePresenceMeta));
        }

        return ParsePresenceMeta(value);
    }

    private static PresenceState ParsePresenceMeta(JsonElement value)
    {
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
        _typingExpiries.Cancel(key);

        Emit(new BackendEvent.TypingChanged(roomId, userId, active));
        if (!active)
        {
            return;
        }

        _typingExpiries.Restart(key);
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
            Interlocked.Increment(ref _overflowCount);
            ScheduleRecovery();
        }
    }

    private void ScheduleRecovery()
    {
        lock (_recoveryGate)
        {
            if (_shutdown.IsCancellationRequested || !_recoveryTask.IsCompleted)
            {
                return;
            }

            _recoveryTask = RecoverAsync();
        }
    }
}
