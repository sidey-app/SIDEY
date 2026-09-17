using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Channels;
using Sidey.Infrastructure.Realtime;

namespace Sidey.Platform.Windows.Tests;

public sealed class SpringRealtimeTransportTests
{
    private static readonly Uri s_origin = new("https://sidey.invalid/api?discarded=true");

    [Fact]
    public async Task RealClientWebSocketUsesBearerHeaderAndReassemblesFragmentedText()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        var headers = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var server = Task.Run(async () =>
        {
            using TcpClient peer = await listener.AcceptTcpClientAsync(deadline.Token);
            using NetworkStream stream = peer.GetStream();
            var request = new StringBuilder();
            byte[] read = new byte[1];
            while (!request.ToString().EndsWith("\r\n\r\n", StringComparison.Ordinal))
            {
                Assert.True(request.Length < 8_192);
                Assert.Equal(1, await stream.ReadAsync(read, deadline.Token));
                request.Append((char)read[0]);
            }
            headers.TrySetResult(request.ToString());
            string key = request.ToString().Split("\r\n").Single(line => line.StartsWith("Sec-WebSocket-Key:", StringComparison.OrdinalIgnoreCase))
                .Split(':', 2)[1].Trim();
            string accept = Convert.ToBase64String(SHA1.HashData(Encoding.ASCII.GetBytes(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")));
            byte[] handshake = Encoding.ASCII.GetBytes("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n");
            await stream.WriteAsync(handshake, deadline.Token);
            await WriteFrameAsync(stream, 0x81, "{\"type\":\"connected\",\"connectionId\":\"wire\"}", deadline.Token);
            await WriteFrameAsync(stream, 0x01, "{\"type\":\"message.created\",", deadline.Token);
            await WriteFrameAsync(stream, 0x80, "\"message\":{\"id\":\"fragmented\"}}", deadline.Token);
            await release.Task.WaitAsync(deadline.Token);
        }, deadline.Token);
        await using var transport = new SpringRealtimeTransport();
        try
        {
            await transport.ConnectAsync(new Uri($"http://127.0.0.1:{port}/api"), "header-only-token", deadline.Token);
            string request = await headers.Task.WaitAsync(deadline.Token);
            Assert.StartsWith("GET /api/realtime HTTP/1.1", request);
            Assert.Contains("Authorization: Bearer header-only-token", request);
            await using IAsyncEnumerator<SpringRealtimeEvent> events = transport.ReadEventsAsync(deadline.Token).GetAsyncEnumerator();
            Assert.True(await events.MoveNextAsync());
            Assert.True(await events.MoveNextAsync());
            JsonElement live = Assert.IsType<SpringRealtimeEvent.Frame>(events.Current).Payload;
            Assert.Equal("fragmented", live.GetProperty("message").GetProperty("id").GetString());
        }
        finally
        {
            release.TrySetResult(true);
            await server;
        }
    }

    [Fact]
    public async Task AuthenticatedHandshakeCorrelatesAckWithoutConsumingLiveMessage()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var socket = new ControlledSocket();
        await using SpringRealtimeTransport transport = Create(socket);
        await transport.ConnectAsync(s_origin, "sidey-access", deadline.Token);
        Assert.Equal("wss://sidey.invalid/api/realtime", socket.Endpoint?.AbsoluteUri);
        Assert.Equal("sidey-access", socket.AccessToken);
        Task<JsonElement> subscribe = transport.CommandAsync(new { type = "subscribe", roomId = "room" }, "subscribe", deadline.Token);
        JsonElement sent = await socket.NextSentAsync(deadline.Token);
        Assert.Equal("subscribe", sent.GetProperty("requestId").GetString());
        socket.Push(new { type = "message.created", message = new { id = "committed" } });
        socket.Push(new { type = "ack", requestId = "subscribe", recoveryThrough = (object?)null });
        Assert.True((await subscribe).TryGetProperty("recoveryThrough", out _));
        await using IAsyncEnumerator<SpringRealtimeEvent> events = transport.ReadEventsAsync(deadline.Token).GetAsyncEnumerator();
        Assert.True(await events.MoveNextAsync());
        Assert.Equal("connected", Assert.IsType<SpringRealtimeEvent.Frame>(events.Current).Payload.GetProperty("type").GetString());
        Assert.True(await events.MoveNextAsync());
        JsonElement live = Assert.IsType<SpringRealtimeEvent.Frame>(events.Current).Payload;
        Assert.Equal("committed", live.GetProperty("message").GetProperty("id").GetString());
    }

    [Fact]
    public async Task TimeoutAndServerErrorReleaseOnlyTheirPendingCommand()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var socket = new ControlledSocket();
        await using SpringRealtimeTransport transport = Create(socket);
        await transport.ConnectAsync(s_origin, "access", deadline.Token);
        SpringRealtimeException timeout = await Assert.ThrowsAsync<SpringRealtimeException>(() =>
            transport.CommandAsync(new { type = "ping" }, "first", deadline.Token, TimeSpan.FromMilliseconds(25)));
        Assert.Equal("command_timeout", timeout.Code);
        _ = await socket.NextSentAsync(deadline.Token);
        Task<JsonElement> denied = transport.CommandAsync(new { type = "message.send" }, "denied", deadline.Token);
        _ = await socket.NextSentAsync(deadline.Token);
        socket.Push(new { type = "error", requestId = "denied", code = "message_id_conflict" });
        Assert.Equal("message_id_conflict", (await Assert.ThrowsAsync<SpringRealtimeException>(() => denied)).Code);
        Task<JsonElement> accepted = transport.CommandAsync(new { type = "message.send" }, "accepted", deadline.Token);
        _ = await socket.NextSentAsync(deadline.Token);
        socket.Push(new { type = "message.ack", requestId = "accepted", message = new { id = "canonical" } });
        Assert.Equal("canonical", (await accepted).GetProperty("message").GetProperty("id").GetString());
    }

    [Fact]
    public async Task PendingCapacityAndCancellationRemainBounded()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        using var cancelled = new CancellationTokenSource();
        var socket = new ControlledSocket();
        await using SpringRealtimeTransport transport = Create(socket, pendingLimit: 1);
        await transport.ConnectAsync(s_origin, "access", deadline.Token);
        Task<JsonElement> pending = transport.CommandAsync(new { type = "ping" }, "one", cancelled.Token);
        _ = await socket.NextSentAsync(deadline.Token);
        Assert.Equal("too_many_commands", (await Assert.ThrowsAsync<SpringRealtimeException>(() =>
            transport.CommandAsync(new { type = "ping" }, "two", deadline.Token))).Code);
        cancelled.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => pending);
        Task<JsonElement> replacement = transport.CommandAsync(new { type = "ping" }, "replacement", deadline.Token);
        _ = await socket.NextSentAsync(deadline.Token);
        socket.Push(new { type = "pong", requestId = "replacement" });
        Assert.Equal("pong", (await replacement).GetProperty("type").GetString());
        Assert.False(socket.Disposed);
    }

    [Fact]
    public async Task IntentionalDisconnectFailsWaitersWithoutStaleCloseNotification()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var socket = new ControlledSocket();
        await using SpringRealtimeTransport transport = Create(socket);
        await transport.ConnectAsync(s_origin, "access", deadline.Token);
        Task<JsonElement> pending = transport.CommandAsync(new { type = "ping" }, "waiting", deadline.Token);
        _ = await socket.NextSentAsync(deadline.Token);
        await transport.DisconnectAsync();
        Assert.Equal("connection_closed", (await Assert.ThrowsAsync<SpringRealtimeException>(() => pending)).Code);
        Assert.True(socket.Disposed);
        await transport.DisposeAsync();
        var received = new List<SpringRealtimeEvent>();
        await foreach (SpringRealtimeEvent item in transport.ReadEventsAsync(deadline.Token))
        {
            received.Add(item);
        }
        Assert.Empty(received);
    }

    [Fact]
    public async Task OldReceiveCannotPublishOrCloseReplacementConnection()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var old = new ControlledSocket(holdReadAfterDispose: true);
        var next = new ControlledSocket();
        var sockets = new Queue<ControlledSocket>([old, next]);
        await using var transport = new SpringRealtimeTransport(() => sockets.Dequeue(), heartbeatInterval: TimeSpan.FromHours(1));
        await transport.ConnectAsync(s_origin, "old", deadline.Token);
        await transport.ConnectAsync(s_origin, "new", deadline.Token);
        old.Push(new { type = "message.created", message = new { id = "stale" } });
        Task<JsonElement> ping = transport.CommandAsync(new { type = "ping" }, "new", deadline.Token);
        _ = await next.NextSentAsync(deadline.Token);
        next.Push(new { type = "pong", requestId = "new" });
        _ = await ping;
        await using IAsyncEnumerator<SpringRealtimeEvent> frames = transport.ReadEventsAsync(deadline.Token).GetAsyncEnumerator();
        Assert.True(await frames.MoveNextAsync());
        Assert.Equal("connected", Assert.IsType<SpringRealtimeEvent.Frame>(frames.Current).Payload.GetProperty("type").GetString());
        next.Push(new { type = "presence", marker = "current" });
        Assert.True(await frames.MoveNextAsync());
        Assert.Equal("current", Assert.IsType<SpringRealtimeEvent.Frame>(frames.Current).Payload.GetProperty("marker").GetString());
    }

    [Fact]
    public async Task QueuedPresenceAndCloseFromPreviousConnectionDoNotReachReplacementConsumer()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var old = new ControlledSocket();
        var next = new ControlledSocket();
        var sockets = new Queue<ControlledSocket>([old, next]);
        await using var transport = new SpringRealtimeTransport(() => sockets.Dequeue(), heartbeatInterval: TimeSpan.FromHours(1));
        await transport.ConnectAsync(s_origin, "old", deadline.Token);
        old.Push(new { type = "presence", marker = "stale" });
        old.Push(new { type = new[] { "invalid" } });
        await old.WhenDisposed.WaitAsync(deadline.Token);
        await transport.ConnectAsync(s_origin, "new", deadline.Token);
        await using IAsyncEnumerator<SpringRealtimeEvent> events = transport.ReadEventsAsync(deadline.Token).GetAsyncEnumerator();
        Assert.True(await events.MoveNextAsync());
        Assert.Equal("connected", Assert.IsType<SpringRealtimeEvent.Frame>(events.Current).Payload.GetProperty("type").GetString());
        next.Push(new { type = "message.created", marker = "current-durable" });
        Assert.True(await events.MoveNextAsync());
        Assert.Equal("current-durable", Assert.IsType<SpringRealtimeEvent.Frame>(events.Current).Payload.GetProperty("marker").GetString());
    }

    [Fact]
    public async Task DurableOverflowClosesWithObservableRecoveryMarker()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var socket = new ControlledSocket();
        await using SpringRealtimeTransport transport = Create(socket, eventCapacity: 1);
        await transport.ConnectAsync(s_origin, "access", deadline.Token);
        socket.Push(new { type = "message.created", message = new { id = "committed" } });
        await socket.WhenDisposed.WaitAsync(deadline.Token);
        await using IAsyncEnumerator<SpringRealtimeEvent> events = transport.ReadEventsAsync(deadline.Token).GetAsyncEnumerator();
        Assert.True(await events.MoveNextAsync());
        Assert.IsType<SpringRealtimeEvent.Closed>(events.Current);
    }

    [Fact]
    public async Task EphemeralOverflowDoesNotCloseHealthyConnection()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var socket = new ControlledSocket();
        await using SpringRealtimeTransport transport = Create(socket, eventCapacity: 1);
        await transport.ConnectAsync(s_origin, "access", deadline.Token);
        socket.Push(new { type = "typing", active = true });
        Task<JsonElement> ping = transport.CommandAsync(new { type = "ping" }, "healthy", deadline.Token);
        _ = await socket.NextSentAsync(deadline.Token);
        socket.Push(new { type = "pong", requestId = "healthy" });
        _ = await ping;
        Assert.False(socket.Disposed);
    }

    [Fact]
    public async Task IncomingAndOutgoingFramesEnforceByteLimit()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var socket = new ControlledSocket();
        await using SpringRealtimeTransport transport = Create(socket);
        await transport.ConnectAsync(s_origin, "access", deadline.Token);
        Assert.Equal("frame_too_large", (await Assert.ThrowsAsync<SpringRealtimeException>(() =>
            transport.SendAsync(new { type = "typing", body = new string('한', 6_000) }, deadline.Token))).Code);
        Assert.False(socket.Disposed);
        socket.PushBytes(new byte[16_385]);
        await socket.WhenDisposed.WaitAsync(deadline.Token);
    }

    [Fact]
    public async Task MissingHandshakeAndBlackholedHeartbeatCloseWithinDeadline()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var stalled = new ControlledSocket(autoConnect: false);
        await using (var transport = new SpringRealtimeTransport(() => stalled, handshakeTimeout: TimeSpan.FromMilliseconds(25)))
        {
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => transport.ConnectAsync(s_origin, "access", deadline.Token));
            Assert.True(stalled.Disposed);
        }
        var quiet = new ControlledSocket();
        await using var live = new SpringRealtimeTransport(() => quiet,
            heartbeatInterval: TimeSpan.FromMilliseconds(15), idleTimeout: TimeSpan.FromMilliseconds(60));
        await live.ConnectAsync(s_origin, "access", deadline.Token);
        JsonElement heartbeat = await quiet.NextSentAsync(deadline.Token);
        Assert.Equal("heartbeat", heartbeat.GetProperty("type").GetString());
        Assert.False(heartbeat.TryGetProperty("requestId", out _));
        await quiet.WhenDisposed.WaitAsync(deadline.Token);
    }

    [Fact]
    public async Task BlockedSendWaitersAreBoundedAndCommandDeadlineClosesSocket()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var socket = new ControlledSocket(blockSends: true);
        await using SpringRealtimeTransport transport = Create(socket, pendingLimit: 1);
        await transport.ConnectAsync(s_origin, "access", deadline.Token);
        Task<JsonElement> blocked = transport.CommandAsync(new { type = "ping" }, "blocked", deadline.Token, TimeSpan.FromMilliseconds(100));
        _ = await socket.NextSentAsync(deadline.Token);
        Assert.Equal("outbound_backpressure", (await Assert.ThrowsAsync<SpringRealtimeException>(() =>
            transport.SendAsync(new { type = "typing" }, deadline.Token))).Code);
        Assert.Equal("command_timeout", (await Assert.ThrowsAsync<SpringRealtimeException>(() => blocked)).Code);
        Assert.True(socket.Disposed);
    }

    private static SpringRealtimeTransport Create(ControlledSocket socket, int eventCapacity = 256, int pendingLimit = 64) =>
        new(() => socket, eventCapacity, pendingLimit, heartbeatInterval: TimeSpan.FromHours(1));

    private static async Task WriteFrameAsync(NetworkStream stream, byte opcode, string text, CancellationToken cancellationToken)
    {
        byte[] payload = Encoding.UTF8.GetBytes(text);
        Assert.True(payload.Length < 126);
        byte[] frame = [opcode, (byte)payload.Length, .. payload];
        await stream.WriteAsync(frame, cancellationToken);
    }

    private sealed class ControlledSocket(bool autoConnect = true, bool holdReadAfterDispose = false, bool blockSends = false)
        : ISpringRealtimeSocket
    {
        private readonly Channel<ReadOnlyMemory<byte>> _incoming = Channel.CreateUnbounded<ReadOnlyMemory<byte>>();
        private readonly Channel<JsonElement> _sent = Channel.CreateUnbounded<JsonElement>();
        private readonly TaskCompletionSource<bool> _disposed = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Uri? Endpoint { get; private set; }
        public string? AccessToken { get; private set; }
        public bool Disposed => _disposed.Task.IsCompleted;
        public Task WhenDisposed => _disposed.Task;

        public Task ConnectAsync(Uri endpoint, string accessToken, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Endpoint = endpoint;
            AccessToken = accessToken;
            if (autoConnect)
            {
                Push(new { type = "connected", connectionId = "test" });
            }
            return Task.CompletedTask;
        }

        public ValueTask<ReadOnlyMemory<byte>> ReceiveAsync(CancellationToken cancellationToken) =>
            _incoming.Reader.ReadAsync(holdReadAfterDispose ? CancellationToken.None : cancellationToken);

        public async ValueTask SendAsync(ReadOnlyMemory<byte> payload, CancellationToken cancellationToken)
        {
            using var frame = JsonDocument.Parse(payload);
            _sent.Writer.TryWrite(frame.RootElement.Clone());
            if (blockSends)
            {
                await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            }
        }

        public ValueTask<JsonElement> NextSentAsync(CancellationToken cancellationToken) => _sent.Reader.ReadAsync(cancellationToken);
        public void Push(object value) => PushBytes(JsonSerializer.SerializeToUtf8Bytes(value));
        public void PushBytes(byte[] bytes) => _incoming.Writer.TryWrite(bytes);

        public void Dispose()
        {
            _disposed.TrySetResult(true);
            if (!holdReadAfterDispose)
            {
                _incoming.Writer.TryComplete(new SpringRealtimeException("connection_closed"));
            }
        }
    }
}
