using System.Diagnostics;
using System.Net.WebSockets;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Channels;

namespace Sidey.Infrastructure.Realtime;

public abstract record SpringRealtimeEvent
{
    public sealed record Frame(JsonElement Payload) : SpringRealtimeEvent;
    public sealed record Closed : SpringRealtimeEvent;
}

public sealed class SpringRealtimeException(string code) : IOException(SideyServiceError.Message(code))
{
    public string Code { get; } = code;
}

/// <summary>Socket-only transport. The gateway owns room subscriptions and REST recovery.</summary>
public sealed class SpringRealtimeTransport : IAsyncDisposable
{
    private const int MaximumFrameBytes = 16_384;
    private readonly Lock _gate = new();
    private readonly Func<ISpringRealtimeSocket> _socketFactory;
    private sealed record QueuedEvent(long Generation, SpringRealtimeEvent Value);
    private readonly Channel<QueuedEvent> _events;
    private long _generation;
    private readonly TimeSpan _heartbeatInterval;
    private readonly TimeSpan _handshakeTimeout;
    private readonly TimeSpan _idleTimeout;
    private readonly int _pendingLimit;
    private Connection? _connection;
    private bool _disposed;

    private sealed class Connection(ISpringRealtimeSocket socket, long generation)
    {
        public long Generation { get; } = generation;
        public ISpringRealtimeSocket Socket { get; } = socket;
        public CancellationTokenSource Lifetime { get; } = new();
        public SemaphoreSlim SendGate { get; } = new(1, 1);
        public TaskCompletionSource<bool> Ready { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Dictionary<string, TaskCompletionSource<JsonElement>> Pending { get; } = [];
        public int Outgoing { get; set; }
        public bool Accepted { get; set; }
        public long LastReceived { get; set; } = Stopwatch.GetTimestamp();
    }

    public SpringRealtimeTransport()
        : this(() => new SpringClientSocket())
    {
    }

    internal SpringRealtimeTransport(
        Func<ISpringRealtimeSocket> socketFactory,
        int eventCapacity = 256,
        int pendingLimit = 64,
        TimeSpan? heartbeatInterval = null,
        TimeSpan? handshakeTimeout = null,
        TimeSpan? idleTimeout = null)
    {
        _socketFactory = socketFactory;
        _pendingLimit = Math.Max(1, pendingLimit);
        _heartbeatInterval = heartbeatInterval ?? TimeSpan.FromSeconds(20);
        _handshakeTimeout = handshakeTimeout ?? TimeSpan.FromSeconds(15);
        _idleTimeout = idleTimeout ?? TimeSpan.FromSeconds(60);
        _events = Channel.CreateBounded<QueuedEvent>(new BoundedChannelOptions(Math.Max(1, eventCapacity))
        {
            FullMode = BoundedChannelFullMode.Wait,
            SingleWriter = false,
            SingleReader = false,
            AllowSynchronousContinuations = false
        });
    }

    public async Task ConnectAsync(Uri apiBase, string accessToken, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(apiBase);
        if (!apiBase.IsAbsoluteUri || apiBase.Scheme is not ("https" or "http")
            || !string.IsNullOrEmpty(apiBase.UserInfo) || string.IsNullOrWhiteSpace(accessToken)
            || accessToken.Contains('\r') || accessToken.Contains('\n'))
        {
            throw new SpringRealtimeException("invalid_connection_configuration");
        }
        var endpoint = new UriBuilder(apiBase)
        {
            Scheme = apiBase.Scheme == "https" ? "wss" : "ws",
            Path = "/api/realtime",
            Query = string.Empty,
            Fragment = string.Empty
        };
        Connection next;
        Connection? previous;
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            next = new Connection(_socketFactory(), ++_generation);
            previous = _connection;
            _connection = next;
        }
        Stop(previous, new SpringRealtimeException("connection_replaced"));
        try
        {
            using var handshake = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, next.Lifetime.Token);
            handshake.CancelAfter(_handshakeTimeout);
            await next.Socket.ConnectAsync(endpoint.Uri, accessToken, handshake.Token).ConfigureAwait(false);
            _ = ReceiveLoopAsync(next);
            await next.Ready.Task.WaitAsync(handshake.Token).ConfigureAwait(false);
            lock (_gate)
            {
                if (!ReferenceEquals(_connection, next))
                {
                    throw new SpringRealtimeException("connection_closed");
                }
            }
            _ = HeartbeatLoopAsync(next);
        }
        catch (Exception exception)
        {
            Close(next, exception);
            throw;
        }
    }

    public async IAsyncEnumerable<SpringRealtimeEvent> ReadEventsAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        await foreach (QueuedEvent frame in _events.Reader.ReadAllAsync(cancellationToken).ConfigureAwait(false))
        {
            lock (_gate)
            { if (frame.Generation != _generation) continue; }
            yield return frame.Value;
        }
    }

    /// <summary>ACK correlation is separate from the client-generated message UUID.</summary>
    public async Task<JsonElement> CommandAsync(object payload, string requestId,
        CancellationToken cancellationToken = default, TimeSpan? timeout = null)
    {
        if (string.IsNullOrEmpty(requestId) || requestId.Length > 128 || requestId.Any(character => character < 32 || character == 127))
        {
            throw new SpringRealtimeException("invalid_request_id");
        }
        JsonObject body = JsonSerializer.SerializeToNode(payload) as JsonObject
            ?? throw new SpringRealtimeException("invalid_command");
        body["requestId"] = requestId;
        byte[] bytes = Encode(body);
        var completion = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
        Connection connection;
        lock (_gate)
        {
            connection = RequireConnection();
            if (connection.Pending.Count >= _pendingLimit)
            {
                throw new SpringRealtimeException("too_many_commands");
            }
            if (!connection.Pending.TryAdd(requestId, completion))
            {
                throw new SpringRealtimeException("duplicate_request_id");
            }
        }
        try
        {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            deadline.CancelAfter(timeout ?? TimeSpan.FromSeconds(15));
            try
            {
                await SendFrameAsync(connection, bytes, deadline.Token).ConfigureAwait(false);
                return await completion.Task.WaitAsync(deadline.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                throw new SpringRealtimeException("command_timeout");
            }
        }
        catch (TimeoutException)
        {
            throw new SpringRealtimeException("command_timeout");
        }
        finally
        {
            lock (_gate)
            {
                if (connection.Pending.TryGetValue(requestId, out TaskCompletionSource<JsonElement>? current)
                    && ReferenceEquals(current, completion))
                {
                    connection.Pending.Remove(requestId);
                }
            }
        }
    }

    public async Task SendAsync(object payload, CancellationToken cancellationToken = default)
    {
        byte[] bytes = Encode(payload);
        Connection connection;
        lock (_gate)
        {
            connection = RequireConnection();
        }
        await SendFrameAsync(connection, bytes, cancellationToken).ConfigureAwait(false);
    }

    public Task DisconnectAsync()
    {
        Connection? connection;
        lock (_gate)
        {
            connection = _connection;
        }
        if (connection is not null)
        {
            Close(connection, new SpringRealtimeException("connection_closed"), notify: false);
        }
        return Task.CompletedTask;
    }

    private Connection RequireConnection()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        return _connection is { Accepted: true } ready ? ready : throw new SpringRealtimeException("connection_closed");
    }

    private static byte[] Encode(object payload)
    {
        byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(payload);
        if (bytes.Length > MaximumFrameBytes)
        {
            throw new SpringRealtimeException("frame_too_large");
        }
        using var document = JsonDocument.Parse(bytes);
        if (document.RootElement.ValueKind != JsonValueKind.Object
            || !document.RootElement.TryGetProperty("type", out JsonElement type)
            || type.ValueKind != JsonValueKind.String || string.IsNullOrEmpty(type.GetString()))
        {
            throw new SpringRealtimeException("invalid_command");
        }
        return bytes;
    }

    private async Task SendFrameAsync(Connection connection, byte[] bytes, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            if (!ReferenceEquals(_connection, connection))
            {
                throw new SpringRealtimeException("connection_closed");
            }
            if (connection.Outgoing >= _pendingLimit)
            {
                throw new SpringRealtimeException("outbound_backpressure");
            }
            connection.Outgoing++;
        }
        bool acquired = false;
        using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, connection.Lifetime.Token);
        lifetime.CancelAfter(TimeSpan.FromSeconds(15));
        try
        {
            await connection.SendGate.WaitAsync(lifetime.Token).ConfigureAwait(false);
            acquired = true;
            await connection.Socket.SendAsync(bytes, lifetime.Token).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            if (acquired)
            {
                Close(connection, exception);
            }
            throw;
        }
        finally
        {
            if (acquired)
            {
                connection.SendGate.Release();
            }
            lock (_gate)
            {
                connection.Outgoing--;
            }
        }
    }

    private async Task ReceiveLoopAsync(Connection connection)
    {
        try
        {
            while (!connection.Lifetime.IsCancellationRequested)
            {
                ReadOnlyMemory<byte> data = await connection.Socket.ReceiveAsync(connection.Lifetime.Token).ConfigureAwait(false);
                if (data.Length > MaximumFrameBytes)
                {
                    throw new SpringRealtimeException("frame_too_large");
                }
                using var document = JsonDocument.Parse(data);
                JsonElement frame = document.RootElement.Clone();
                if (frame.ValueKind != JsonValueKind.Object || !frame.TryGetProperty("type", out JsonElement kind)
                    || kind.ValueKind != JsonValueKind.String)
                {
                    throw new SpringRealtimeException("invalid_frame");
                }
                string type = kind.GetString()!;
                bool overflow = false;
                lock (_gate)
                {
                    if (!ReferenceEquals(_connection, connection))
                    {
                        return;
                    }
                    connection.LastReceived = Stopwatch.GetTimestamp();
                    if (!connection.Accepted)
                    {
                        if (type != "connected")
                        {
                            throw new SpringRealtimeException("handshake_rejected");
                        }
                        connection.Accepted = true;
                        connection.Ready.TrySetResult(true);
                    }
                    if (type is "ack" or "message.ack" or "pong" or "error"
                        && frame.TryGetProperty("requestId", out JsonElement correlation)
                        && correlation.ValueKind == JsonValueKind.String
                        && connection.Pending.Remove(correlation.GetString()!, out TaskCompletionSource<JsonElement>? pending))
                    {
                        if (type == "error")
                        {
                            string code = frame.TryGetProperty("code", out JsonElement error) && error.ValueKind == JsonValueKind.String
                                ? error.GetString()! : "unknown_error";
                            pending.TrySetException(new SpringRealtimeException(code));
                        }
                        else
                        {
                            pending.TrySetResult(frame);
                        }
                        continue;
                    }
                    if (type != "heartbeat.ack" && !_events.Writer.TryWrite(new QueuedEvent(connection.Generation, new SpringRealtimeEvent.Frame(frame))))
                    {
                        overflow = type is not ("presence" or "typing" or "character.pulse" or "character.throw" or "pong" or "connected");
                    }
                }
                if (overflow)
                {
                    throw new SpringRealtimeException("durable_event_overflow");
                }
            }
        }
        catch (Exception exception)
        {
            Close(connection, exception);
        }
    }

    private async Task HeartbeatLoopAsync(Connection connection)
    {
        try
        {
            while (!connection.Lifetime.IsCancellationRequested)
            {
                await Task.Delay(_heartbeatInterval, connection.Lifetime.Token).ConfigureAwait(false);
                lock (_gate)
                {
                    if (Stopwatch.GetElapsedTime(connection.LastReceived) >= _idleTimeout)
                    {
                        throw new SpringRealtimeException("heartbeat_timeout");
                    }
                }
                await SendFrameAsync(connection, Encode(new { type = "heartbeat" }), connection.Lifetime.Token).ConfigureAwait(false);
            }
        }
        catch (Exception exception)
        {
            Close(connection, exception);
        }
    }

    private void Close(Connection connection, Exception exception, bool notify = true)
    {
        lock (_gate)
        {
            if (!ReferenceEquals(_connection, connection))
            {
                return;
            }
            _connection = null;
            if (!notify)
                _generation++;
            // A closed marker must remain observable even when the reader stalled.
            // Evicted durable events will be recovered through PostgreSQL history.
            while (notify && !_events.Writer.TryWrite(new QueuedEvent(connection.Generation, new SpringRealtimeEvent.Closed())))
            {
                if (!_events.Reader.TryRead(out _))
                {
                    break;
                }
            }
        }
        Stop(connection, exception);
    }

    private void Stop(Connection? connection, Exception exception)
    {
        if (connection is null)
        {
            return;
        }
        TaskCompletionSource<JsonElement>[] waiting;
        lock (_gate)
        {
            waiting = [.. connection.Pending.Values];
            connection.Pending.Clear();
        }
        connection.Ready.TrySetException(exception);
        foreach (TaskCompletionSource<JsonElement> pending in waiting)
        {
            pending.TrySetException(exception);
        }
        connection.Lifetime.Cancel();
        connection.Socket.Dispose();
    }

    public async ValueTask DisposeAsync()
    {
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }
            _disposed = true;
        }
        await DisconnectAsync().ConfigureAwait(false);
        _events.Writer.TryComplete();
    }
}

internal interface ISpringRealtimeSocket : IDisposable
{
    public Task ConnectAsync(Uri endpoint, string accessToken, CancellationToken cancellationToken);
    public ValueTask<ReadOnlyMemory<byte>> ReceiveAsync(CancellationToken cancellationToken);
    public ValueTask SendAsync(ReadOnlyMemory<byte> payload, CancellationToken cancellationToken);
}

internal sealed class SpringClientSocket : ISpringRealtimeSocket
{
    private readonly ClientWebSocket _socket = new();

    public Task ConnectAsync(Uri endpoint, string accessToken, CancellationToken cancellationToken)
    {
        _socket.Options.SetRequestHeader("Authorization", "Bearer " + accessToken);
        return _socket.ConnectAsync(endpoint, cancellationToken);
    }

    public async ValueTask<ReadOnlyMemory<byte>> ReceiveAsync(CancellationToken cancellationToken)
    {
        byte[] buffer = new byte[16_384];
        int length = 0;
        while (true)
        {
            ValueWebSocketReceiveResult result = await _socket.ReceiveAsync(buffer.AsMemory(length), cancellationToken).ConfigureAwait(false);
            if (result.MessageType != WebSocketMessageType.Text)
            {
                throw new SpringRealtimeException("connection_closed");
            }
            length += result.Count;
            if (result.EndOfMessage)
            {
                return buffer.AsMemory(0, length);
            }
            if (length == buffer.Length)
            {
                throw new SpringRealtimeException("frame_too_large");
            }
        }
    }

    public async ValueTask SendAsync(ReadOnlyMemory<byte> payload, CancellationToken cancellationToken)
    {
        await _socket.SendAsync(payload, WebSocketMessageType.Text, true, cancellationToken).ConfigureAwait(false);
    }

    public void Dispose() => _socket.Dispose();
}
