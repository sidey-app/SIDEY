using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Threading.Channels;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;

namespace Sidey.Infrastructure.ContractTests;

public sealed class SpringGatewayTests
{
    [Fact]
    public async Task FreshAuthoritativeSnapshotRestoresRejoinedRoomAfterDelayedRevocation()
    {
        await using var fixture = new Fixture();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await fixture.RecoverAsync(deadline.Token);
        fixture.Push(new { type = "room.revoked", roomId = fixture.Room });
        await using IAsyncEnumerator<BackendEvent> events = fixture.Gateway.SubscribeAsync(deadline.Token).GetAsyncEnumerator();
        while (await events.MoveNextAsync())
        {
            if (events.Current is BackendEvent.RoomRevoked)
                break;
        }
        // A rejoin already committed, so the next authoritative response contains the room.
        await fixture.RecoverAsync(deadline.Token);
        Assert.Equal(231, (await fixture.Gateway.FetchRecentMessagesAsync(fixture.Room, deadline.Token)).Count);
        Assert.Equal(2, fixture.SubscribeCount);
        while (await events.MoveNextAsync())
        {
            if (events.Current is BackendEvent.SnapshotReceived snapshot)
            {
                Assert.True(snapshot.Snapshot.MembershipRevision > 0);
                Assert.Equal(fixture.Room, Assert.Single(snapshot.Snapshot.Rooms).Id);
                break;
            }
        }
    }

    [Fact]
    public async Task TargetedRevocationImmediatelyClearsRoomWhileStaleRestSnapshotIsBlocked()
    {
        await using var fixture = new Fixture();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await fixture.RecoverAsync(deadline.Token);
        var revoked = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var recovered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var events = new ConcurrentQueue<BackendEvent>();
        var consumer = Task.Run(async () =>
        {
            await foreach (BackendEvent value in fixture.Gateway.SubscribeAsync(deadline.Token))
            {
                events.Enqueue(value);
                if (value is BackendEvent.RoomRevoked)
                    revoked.TrySetResult();
                if (value is BackendEvent.SnapshotReceived snapshot && snapshot.Snapshot.MembershipRevision > 0)
                {
                    Assert.Empty(snapshot.Snapshot.Rooms);
                    recovered.TrySetResult();
                }
            }
        }, deadline.Token);
        try
        {
            fixture.HoldSnapshot = true;
            Task staleRecovery = fixture.RecoverAsync(deadline.Token);
            await fixture.SnapshotCaptured.Task.WaitAsync(deadline.Token);
            fixture.Revoked = true;
            fixture.Push(new { type = "room.revoked", roomId = fixture.Room });
            await revoked.Task.WaitAsync(deadline.Token);
            Assert.False(staleRecovery.IsCompleted);
            Assert.Single(events.OfType<BackendEvent.RoomRevoked>());
            fixture.Push(new
            {
                type = "presence",
                roomId = fixture.Room,
                members = new Dictionary<Guid, string> { [fixture.User] = "ONLINE" }
            });
            fixture.Push(new
            {
                type = "message.created",
                message = new ChatMessage(Guid.NewGuid(), fixture.Room,
                fixture.User, "stale live", DateTimeOffset.UtcNow)
            });
            fixture.ReleaseSnapshot.SetResult();
            await staleRecovery.WaitAsync(deadline.Token);
            await recovered.Task.WaitAsync(deadline.Token);
            BackendEvent[] after = [.. events.SkipWhile(value => value is not BackendEvent.RoomRevoked).Skip(1)];
            Assert.DoesNotContain(after, value => value is BackendEvent.MessageReceived or BackendEvent.MessagesReplaced
                or BackendEvent.PresenceChanged or BackendEvent.TypingChanged);
            Assert.DoesNotContain(fixture.PublishedPresence, room => room == fixture.Room);
            Assert.Equal(1, fixture.SubscribeCount);
        }
        finally
        {
            fixture.ReleaseSnapshot.TrySetResult();
            await deadline.CancelAsync();
            try
            { await consumer; }
            catch (OperationCanceledException) { }
        }
    }

    [Fact]
    public async Task ForcedReconnectRetriesConnectionAfterSnapshotFailure()
    {
        await using var fixture = new Fixture();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await fixture.RecoverAsync(deadline.Token);
        fixture.FailSnapshot = true;
        fixture.Gateway.RetryRealtimeConnection();
        await Assert.ThrowsAsync<SideyApiException>(() => fixture.RecoverAsync(deadline.Token));
        await fixture.RecoverAsync(deadline.Token);
        Assert.Equal(231, (await fixture.Gateway.FetchRecentMessagesAsync(fixture.Room, deadline.Token)).Count);
    }

    [Fact]
    public async Task SubscribeFirstReadsEveryPageAndMergesLiveWithoutAdvancingCheckpoint()
    {
        await using var fixture = new Fixture();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await fixture.RecoverAsync(deadline.Token);
        IReadOnlyList<ChatMessage> messages = await fixture.Gateway.FetchRecentMessagesAsync(fixture.Room, deadline.Token);
        Assert.Equal(231, messages.Count);
        Assert.Equal(231, messages.Select(message => message.Id).Distinct().Count());
        Assert.Equal(new string?[] { null, fixture.Id(199).ToString("D") }, fixture.AfterIds.ToArray());
        await fixture.RecoverAsync(deadline.Token);
        Assert.Equal(fixture.Id(229).ToString("D"), fixture.AfterIds.Last());
        Assert.Equal(231, (await fixture.Gateway.FetchRecentMessagesAsync(fixture.Room, deadline.Token)).Count);
    }

    [Fact]
    public async Task FailedSecondPageDoesNotSkipUnconfirmedHistoryOnRetry()
    {
        await using var fixture = new Fixture { FailSecondPage = true };
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await Assert.ThrowsAsync<SideyApiException>(() => fixture.RecoverAsync(deadline.Token));
        await fixture.RecoverAsync(deadline.Token);
        Assert.Equal(new string?[] { null, fixture.Id(199).ToString("D"), null, fixture.Id(199).ToString("D") }, fixture.AfterIds.ToArray());
        Assert.Equal(231, (await fixture.Gateway.FetchRecentMessagesAsync(fixture.Room, deadline.Token)).Count);
    }

    [Fact]
    public async Task CommittedMessageIsRecoveredAfterLostAckAndRetryKeepsItsSnapshot()
    {
        await using var fixture = new Fixture { LoseFirstAck = true };
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await fixture.RecoverAsync(deadline.Token);
        var id = Guid.NewGuid();
        ChatMessage first = await fixture.Gateway.SendMessageAsync(id, fixture.Room, "  hello  ", deadline.Token);
        ChatMessage retry = await fixture.Gateway.SendMessageAsync(id, fixture.Room, "  hello  ", deadline.Token);
        Assert.Equal(first, retry);
        Assert.Equal("hello", retry.Body);
        Assert.Equal("bubble_bunny_pink", retry.BubbleStyleId);
        Assert.Single(fixture.Committed);
        SpringRealtimeException conflict = await Assert.ThrowsAsync<SpringRealtimeException>(() =>
            fixture.Gateway.SendMessageAsync(id, fixture.Room, "changed", deadline.Token));
        Assert.Equal("message_id_conflict", conflict.Code);
        Assert.Single(fixture.Committed);
    }

    [Fact]
    public void LedgerKeepsLiveMaximumSeparateFromCompletedCursorAndPrunesRetention()
    {
        var ledger = new SpringMessageLedger(2);
        DateTimeOffset now = DateTimeOffset.UtcNow;
        var cursor = new MessageHistoryCursor(now.AddMinutes(-5), Guid.NewGuid());
        ledger.CompleteRecovery(cursor);
        var live = new ChatMessage(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), "live", now);
        Assert.True(ledger.Merge(live));
        Assert.False(ledger.Merge(live));
        ledger.Merge(live with { Id = Guid.NewGuid(), CreatedAt = now.AddDays(-4) });
        ledger.Prune(now);
        Assert.Single(ledger.Messages);
        Assert.Equal(cursor, ledger.ConfirmedCursor);
    }

    private sealed class Fixture : HttpMessageHandler, ICredentialStore, IAsyncDisposable
    {
        private static readonly JsonSerializerOptions s_json = new(JsonSerializerDefaults.Web);
        private readonly Dictionary<CredentialKey, string> _credentials = [];
        private readonly DateTimeOffset _baseTime = DateTimeOffset.UtcNow.AddHours(-1).ToOffset(TimeSpan.FromHours(9));
        private readonly HttpClient _http;
        private readonly SideyAuthService _auth;
        private bool _subscribed;
        private Socket? _socket;
        public bool Revoked { get; set; }
        public bool HoldSnapshot { get; set; }
        public int SubscribeCount { get; private set; }
        public ConcurrentQueue<Guid?> PublishedPresence { get; } = new();
        public TaskCompletionSource SnapshotCaptured { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource ReleaseSnapshot { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public void Push(object value) => _socket!.Push(value);
        public Guid User { get; } = Guid.NewGuid();
        public Guid Room { get; } = Guid.NewGuid();
        public SpringBackendGateway Gateway { get; }
        public bool FailSecondPage { get; set; }
        public bool FailSnapshot { get; set; }
        public bool LoseFirstAck { get; set; }
        public ConcurrentQueue<string?> AfterIds { get; } = new();
        public ConcurrentDictionary<Guid, ChatMessage> Committed { get; } = new();

        public Fixture()
        {
            var configuration = new SideyRuntimeConfiguration(new Uri("https://sidey.invalid/api"));
            _credentials[CredentialKey.SideySession] = JsonSerializer.Serialize(new SideySession(User, Guid.NewGuid(),
                "access", "refresh", DateTimeOffset.UtcNow.AddMinutes(15)), s_json);
            _http = new HttpClient(this);
            _auth = new SideyAuthService(configuration, this, _http);
            var transport = new SpringRealtimeTransport(() => _socket = new Socket(this));
            Gateway = new SpringBackendGateway(configuration, _auth, this, transport);
        }

        public Guid Id(int index) => Guid.Parse($"00000000-0000-0000-0000-{index + 1:000000000000}");
        private ChatMessage Message(int index) => new(Id(index), Room, User, $"message {index}", _baseTime.AddTicks(index * 10), "bubble_bunny_pink");
        private MessageHistoryCursor Cursor(int index) => new(Message(index).CreatedAt, Id(index));
        public Task RecoverAsync(CancellationToken token) => Gateway.SynchronizeRealtimeRoomsAsync(
            Room, PresenceState.Online, token);

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Assert.Equal("Bearer", request.Headers.Authorization?.Scheme);
            Assert.Equal("access", request.Headers.Authorization?.Parameter);
            string path = request.RequestUri!.AbsolutePath;
            object result;
            if (path == "/api/profile")
            {
                if (FailSnapshot)
                {
                    FailSnapshot = false;
                    return new HttpResponseMessage(HttpStatusCode.ServiceUnavailable) { Content = JsonContent.Create(new { code = "fixture_failure" }) };
                }
                result = new Profile(User, "Friend", "pixel_hamster", TreeMovementRevision: 0);
            }
            else if (path == "/api/rooms")
            {
                result = Revoked ? [] : (object[])[new { id = Room, name = "Room", ownerId = User, inviteCodeHint = "ABCD", inviteVersion = 1,
                    members = new[] { new { userId = User, profile = new Profile(User, "Friend", "pixel_hamster", TreeMovementRevision: 0) } } }];
                if (HoldSnapshot)
                {
                    HoldSnapshot = false;
                    PublishedPresence.Clear();
                    SnapshotCaptured.TrySetResult();
                    await ReleaseSnapshot.Task.WaitAsync(cancellationToken);
                }
            }
            else if (path == "/api/commerce/entitlements")
            { result = Array.Empty<object>(); }
            else if (path == $"/api/rooms/{Room:D}/messages")
            {
                Assert.True(_subscribed, "Live subscription must precede every REST catch-up request.");
                var query = request.RequestUri.Query.TrimStart('?').Split('&')
                    .Select(value => value.Split('=', 2)).ToDictionary(value => value[0], value => Uri.UnescapeDataString(value[1]));
                string? after = query.GetValueOrDefault("afterId");
                AfterIds.Enqueue(after);
                Assert.Equal(Id(229).ToString("D"), query["throughId"]);
                Assert.Equal(Cursor(229).CreatedAt, DateTimeOffset.Parse(query["throughCreatedAt"]));
                if (after is not null)
                {
                    int index = after == Id(199).ToString("D") ? 199 : 229;
                    Assert.Equal(Cursor(index).CreatedAt, DateTimeOffset.Parse(query["afterCreatedAt"]));
                }
                if (after == Id(199).ToString("D") && FailSecondPage)
                {
                    FailSecondPage = false;
                    return new HttpResponseMessage(HttpStatusCode.ServiceUnavailable) { Content = JsonContent.Create(new { code = "fixture_failure" }) };
                }
                int start = after is null ? 0 : after == Id(199).ToString("D") ? 200 : 230;
                ChatMessage[] messages = [.. Enumerable.Range(start, Math.Min(200, 230 - start)).Select(Message)];
                result = new MessageHistoryPage(messages, start == 0 ? Cursor(199) : null);
            }
            else if (path.StartsWith($"/api/rooms/{Room:D}/messages/", StringComparison.Ordinal))
            {
                var id = Guid.Parse(path.Split('/').Last());
                if (!Committed.TryGetValue(id, out ChatMessage? message))
                {
                    return new HttpResponseMessage(HttpStatusCode.NotFound) { Content = JsonContent.Create(new { code = "message_missing" }) };
                }
                result = message;
            }
            else
            { throw new InvalidOperationException("Unexpected API request: " + path); }
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(result, options: s_json) };
        }

        private sealed class Socket(Fixture fixture) : ISpringRealtimeSocket
        {
            private readonly Channel<ReadOnlyMemory<byte>> _incoming = Channel.CreateUnbounded<ReadOnlyMemory<byte>>();
            public Task ConnectAsync(Uri endpoint, string accessToken, CancellationToken cancellationToken)
            {
                Assert.Equal("access", accessToken);
                Push(new { type = "connected" });
                return Task.CompletedTask;
            }
            public void Push(object value) => _incoming.Writer.TryWrite(JsonSerializer.SerializeToUtf8Bytes(value, s_json));
            public ValueTask<ReadOnlyMemory<byte>> ReceiveAsync(CancellationToken cancellationToken) => _incoming.Reader.ReadAsync(cancellationToken);
            public ValueTask SendAsync(ReadOnlyMemory<byte> payload, CancellationToken cancellationToken)
            {
                using var document = JsonDocument.Parse(payload);
                JsonElement command = document.RootElement;
                string? type = command.GetProperty("type").GetString();
                string? requestId = command.TryGetProperty("requestId", out JsonElement request) ? request.GetString() : null;
                if (type == "subscribe")
                {
                    fixture._subscribed = true;
                    fixture.SubscribeCount++;
                    Push(new { type = "message.created", message = fixture.Message(230) });
                    Push(new { type = "ack", command = "subscribe", requestId, roomId = fixture.Room, recoveryThrough = fixture.Cursor(229) });
                }
                else if (type == "presence.update")
                {
                    fixture.PublishedPresence.Enqueue(command.GetProperty("activeRoomId").ValueKind == JsonValueKind.Null
                        ? null : command.GetProperty("activeRoomId").GetGuid());
                }
                else if (type == "message.send")
                {
                    Guid id = command.GetProperty("id").GetGuid();
                    string body = command.GetProperty("body").GetString()!;
                    ChatMessage canonical = fixture.Committed.GetOrAdd(id, new ChatMessage(id, fixture.Room, fixture.User, body,
                        DateTimeOffset.UtcNow, "bubble_bunny_pink"));
                    if (canonical.Body != body)
                    { Push(new { type = "error", requestId, code = "message_id_conflict" }); }
                    else if (fixture.LoseFirstAck)
                    {
                        fixture.LoseFirstAck = false;
                        Push(new { type = "error", requestId, code = "response_lost_after_commit" });
                    }
                    else
                    { Push(new { type = "message.ack", requestId, message = canonical }); }
                }
                return ValueTask.CompletedTask;
            }
            public void Dispose() => _incoming.Writer.TryComplete();
        }

        public ValueTask<string?> ReadAsync(CredentialKey key, CancellationToken cancellationToken = default) => ValueTask.FromResult(_credentials.GetValueOrDefault(key));
        public ValueTask WriteAsync(CredentialKey key, string value, CancellationToken cancellationToken = default) { _credentials[key] = value; return ValueTask.CompletedTask; }
        public ValueTask DeleteAsync(CredentialKey key, CancellationToken cancellationToken = default) { _credentials.Remove(key); return ValueTask.CompletedTask; }
        public ValueTask<string?> ReadInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default) => ValueTask.FromResult<string?>(null);
        public ValueTask WriteInviteCodeAsync(Guid roomId, string inviteCode, CancellationToken cancellationToken = default) => ValueTask.CompletedTask;
        public ValueTask DeleteInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default) => ValueTask.CompletedTask;
        public async ValueTask DisposeAsync() { await Gateway.DisposeAsync(); _auth.Dispose(); _http.Dispose(); }
    }
}
