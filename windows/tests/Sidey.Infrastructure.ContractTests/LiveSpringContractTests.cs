using System.Text.Json;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Infrastructure.Authentication;
using Sidey.Infrastructure.Backend;
using Sidey.Infrastructure.Configuration;
using Sidey.Infrastructure.Realtime;

namespace Sidey.Infrastructure.ContractTests;

public sealed class LiveSpringContractAttribute : FactAttribute
{
    public LiveSpringContractAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("SIDEY_LIVE_CONTRACT_FIXTURE")))
            Skip = "Requires disposable local Spring sessions in SIDEY_LIVE_CONTRACT_FIXTURE.";
    }
}

public sealed class LiveSpringContractTests
{
    [LiveSpringContract]
    public async Task RealRestAndWebSocketRecoverCommittedChatAndRevokeRoomAndSessionAccess()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(45));
        string fixturePath = Environment.GetEnvironmentVariable("SIDEY_LIVE_CONTRACT_FIXTURE")!;
        using var fixture = JsonDocument.Parse(await File.ReadAllTextAsync(fixturePath, deadline.Token));
        var api = new Uri(fixture.RootElement.GetProperty("apiBase").GetString()!);
        Assert.True(api.IsLoopback, "Live fixture must target a disposable loopback backend.");
        var configuration = new SideyRuntimeConfiguration(api);
        SideySession original = fixture.RootElement.GetProperty("sessions")[0]
            .Deserialize<SideySession>(new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
        var firstCredentials = new Credentials(JsonSerializer.Serialize(original with
        { AccessExpiresAt = DateTimeOffset.UtcNow.AddMinutes(-1) }, new JsonSerializerOptions(JsonSerializerDefaults.Web)));
        var secondCredentials = new Credentials(fixture.RootElement.GetProperty("sessions")[1].GetRawText());
        using var firstAuth = new SideyAuthService(configuration, firstCredentials);
        using var secondAuth = new SideyAuthService(configuration, secondCredentials);
        await using var secondTransport = new SpringRealtimeTransport();
        await using var first = new SpringBackendGateway(configuration, firstAuth, firstCredentials);
        await using var second = new SpringBackendGateway(configuration, secondAuth, secondCredentials, secondTransport);
        SideySession firstSession = await firstAuth.GetSessionAsync(deadline.Token);
        Assert.Equal(original.SessionId, firstSession.SessionId);
        Assert.True(original.RefreshToken != firstSession.RefreshToken, "Expired access requires real refresh rotation.");
        CreateRoomResult created = await first.CreateRoomAsync("Contract room", deadline.Token);
        await second.JoinRoomAsync(created.InviteCode, deadline.Token);
        var firstMessage = new TaskCompletionSource<ChatMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
        var away = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var revoked = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var consume = Task.Run(async () =>
        {
            await foreach (BackendEvent value in second.SubscribeAsync(deadline.Token))
            {
                if (value is BackendEvent.MessageReceived message)
                    firstMessage.TrySetResult(message.Message);
                if (value is BackendEvent.PresenceChanged presence && presence.UserId == firstSession.UserId
                    && presence.State == PresenceState.Away)
                    away.TrySetResult();
                if (value is BackendEvent.RoomRevoked)
                    revoked.TrySetResult();
            }
        }, deadline.Token);
        try
        {
            await first.SynchronizeRealtimeRoomsAsync(created.Room.Id, PresenceState.Online, deadline.Token);
            await second.SynchronizeRealtimeRoomsAsync(created.Room.Id, PresenceState.Online, deadline.Token);
            var id = Guid.NewGuid();
            ChatMessage sent = await first.SendMessageAsync(id, created.Room.Id, "contract message", deadline.Token);
            Assert.Equal(sent, await firstMessage.Task.WaitAsync(deadline.Token));
            Assert.Equal(sent, await first.SendMessageAsync(id, created.Room.Id, "contract message", deadline.Token));
            await Assert.ThrowsAsync<SpringRealtimeException>(() => first.SendMessageAsync(id, created.Room.Id,
                "different message", deadline.Token));

            await secondTransport.DisconnectAsync();
            second.RetryRealtimeConnection();
            ChatMessage missed = await first.SendMessageAsync(Guid.NewGuid(), created.Room.Id, "catch up", deadline.Token);
            await second.SynchronizeRealtimeRoomsAsync(created.Room.Id, PresenceState.Online, deadline.Token);
            IReadOnlyList<ChatMessage> recovered = await second.FetchRecentMessagesAsync(created.Room.Id, deadline.Token);
            Assert.Equal(2, recovered.Count);
            Assert.Contains(recovered, message => message == missed);
            Assert.Equal(2, recovered.Select(message => message.Id).Distinct().Count());

            await first.PublishPresenceAsync(created.Room.Id, PresenceState.Away, deadline.Token);
            await away.Task.WaitAsync(deadline.Token);
            SideySession secondSession = await secondAuth.GetSessionAsync(deadline.Token);
            await first.RemoveRoomMemberAsync(created.Room.Id, secondSession.UserId, deadline.Token);
            await revoked.Task.WaitAsync(deadline.Token);
            await Assert.ThrowsAsync<SideyApiException>(() => second.FetchMessagePageAsync(created.Room.Id, null,
                cancellationToken: deadline.Token));
            await first.DeleteRoomAsync(created.Room.Id, deadline.Token);
            await secondAuth.DeleteAccountAsync(deadline.Token);
            await firstAuth.SignOutAllAsync(deadline.Token);
            await Assert.ThrowsAsync<AuthenticationRequiredException>(() => firstAuth.GetSessionAsync(deadline.Token));
        }
        finally
        {
            await deadline.CancelAsync();
            try
            { await consume; }
            catch (OperationCanceledException) { }
        }
    }

    private sealed class Credentials(string session) : ICredentialStore
    {
        private string? _session = session;
        public ValueTask<string?> ReadAsync(CredentialKey key, CancellationToken cancellationToken = default) =>
            ValueTask.FromResult(key == CredentialKey.SideySession ? _session : null);
        public ValueTask WriteAsync(CredentialKey key, string value, CancellationToken cancellationToken = default)
        { if (key == CredentialKey.SideySession) _session = value; return ValueTask.CompletedTask; }
        public ValueTask DeleteAsync(CredentialKey key, CancellationToken cancellationToken = default)
        { if (key == CredentialKey.SideySession) _session = null; return ValueTask.CompletedTask; }
        public ValueTask<string?> ReadInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default) => ValueTask.FromResult<string?>(null);
        public ValueTask WriteInviteCodeAsync(Guid roomId, string inviteCode, CancellationToken cancellationToken = default) => ValueTask.CompletedTask;
        public ValueTask DeleteInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default) => ValueTask.CompletedTask;
    }
}
