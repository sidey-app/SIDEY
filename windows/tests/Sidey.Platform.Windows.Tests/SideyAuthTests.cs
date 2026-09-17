using System.Collections.Concurrent;
using System.Net;
using System.Text;
using System.Text.Json;
using Sidey.Core.Abstractions;
using Sidey.Infrastructure.Authentication;
using Sidey.Infrastructure.Configuration;

namespace Sidey.Platform.Windows.Tests;

public sealed class SideyAuthTests
{
    private static readonly DateTimeOffset s_now = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
    private static readonly JsonSerializerOptions s_json = new(JsonSerializerDefaults.Web);
    private static readonly Guid s_user = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid s_sid = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly SideyRuntimeConfiguration s_configuration = new(new Uri("https://spring.test/api"));

    [Fact]
    public async Task NewInstallDoesNotPerformAnonymousSignup()
    {
        using var fixture = new Fixture();
        Assert.Null(await fixture.Auth.RestoreSessionAsync());
        await Assert.ThrowsAsync<AuthenticationRequiredException>(() => fixture.Auth.GetSessionAsync());
        Assert.Empty(fixture.Network.Requests);
    }

    [Fact]
    public async Task ConcurrentExpiredSessionAccessRotatesExactlyOnce()
    {
        using var fixture = new Fixture();
        fixture.Credentials.Values[CredentialKey.SideySession] = SessionJson(expired: true);
        fixture.Network.Reply(SessionJson(access: "new-access", refresh: "new-refresh"));
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Network.ResponseGate = release.Task;
        Task<SideySession>[] pending = [.. Enumerable.Range(0, 20).Select(_ => fixture.Auth.GetSessionAsync())];
        await fixture.Network.FirstRequest.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Single(fixture.Network.Requests);
        release.SetResult();
        SideySession[] sessions = await Task.WhenAll(pending);
        Assert.All(sessions, session => Assert.Equal("new-access", session.AccessToken));
        Assert.Single(fixture.Network.Requests);
        Assert.Equal("/api/auth/refresh", fixture.Network.Requests[0].Path);
        Assert.Contains("new-refresh", fixture.Credentials.Values[CredentialKey.SideySession]);
    }

    [Fact]
    public async Task RejectedAccessRefreshesOnceWithoutReplayingArbitraryFailures()
    {
        using var fixture = new Fixture();
        fixture.Credentials.Values[CredentialKey.SideySession] = SessionJson();
        fixture.Network.Reply("{}", HttpStatusCode.Unauthorized);
        fixture.Network.Reply(SessionJson(access: "rotated"));
        fixture.Network.Reply("{\"rooms\":[]}");
        _ = await fixture.Auth.SendAsync(HttpMethod.Get, "/rooms");
        Assert.Equal(["/api/rooms", "/api/auth/refresh", "/api/rooms"], fixture.Network.Requests.Select(request => request.Path));
        Assert.Equal("rotated", fixture.Network.Requests[2].Token);
        fixture.Network.Reply("{\"code\":\"database_unavailable\"}", HttpStatusCode.ServiceUnavailable);
        SideyApiException error = await Assert.ThrowsAsync<SideyApiException>(() => fixture.Auth.SendAsync(HttpMethod.Post, "rooms", new { name = "group" }));
        Assert.Equal("database_unavailable", error.Code);
        Assert.Equal(4, fixture.Network.Requests.Count);
    }

    [Fact]
    public async Task UncertainRotationFailureNeverReusesOldRefresh()
    {
        using var fixture = new Fixture();
        fixture.Credentials.Values[CredentialKey.SideySession] = SessionJson(expired: true);
        fixture.Network.Reply("{}", HttpStatusCode.ServiceUnavailable);
        await Assert.ThrowsAsync<AuthenticationRequiredException>(() => fixture.Auth.GetSessionAsync());
        await Assert.ThrowsAsync<AuthenticationRequiredException>(() => fixture.Auth.GetSessionAsync());
        Assert.Single(fixture.Network.Requests);
        Assert.False(fixture.Credentials.Values.ContainsKey(CredentialKey.SideySession));
    }

    [Fact]
    public async Task FailedRotatedCredentialWriteCannotReuseConsumedRefreshToken()
    {
        using var fixture = new Fixture();
        fixture.Credentials.Values[CredentialKey.SideySession] = SessionJson(expired: true);
        fixture.Credentials.RejectSideyWrite = true;
        fixture.Network.Reply(SessionJson(access: "new-access", refresh: "new-refresh"));
        await Assert.ThrowsAsync<AuthenticationRequiredException>(() => fixture.Auth.GetSessionAsync());
        await Assert.ThrowsAsync<AuthenticationRequiredException>(() => fixture.Auth.GetSessionAsync());
        Assert.Single(fixture.Network.Requests);
        Assert.False(fixture.Credentials.Values.ContainsKey(CredentialKey.SideySession));
    }

    [Fact]
    public async Task LastProviderUnlinkFailurePreservesActiveSideySession()
    {
        using var fixture = new Fixture();
        fixture.Credentials.Values[CredentialKey.SideySession] = SessionJson();
        fixture.Network.Reply("{\"code\":\"last_identity_unlink_forbidden\"}", HttpStatusCode.Conflict);
        SideyApiException error = await Assert.ThrowsAsync<SideyApiException>(() =>
            fixture.Auth.UnlinkAsync("APPLE", "fresh-proof", "fresh-nonce"));
        Assert.Equal("last_identity_unlink_forbidden", error.Code);
        Assert.Equal(s_sid, (await fixture.Auth.GetSessionAsync()).SessionId);
        Assert.Single(fixture.Network.Requests);
        Assert.Contains("fresh-proof", fixture.Network.Requests[0].Body);
    }

    [Fact]
    public async Task LegacyClaimUsesOldCredentialAndPreservesUuidBeforeDeletingProof()
    {
        using var fixture = new Fixture();
        fixture.Credentials.Values[CredentialKey.SupabaseSession] = LegacyJson();
        await Assert.ThrowsAsync<LegacyClaimRequiredException>(() => fixture.Auth.RestoreSessionAsync());
        fixture.Network.Reply(SessionJson());
        await fixture.Auth.AuthenticateAsync("GOOGLE", "provider-proof", "nonce");
        Assert.Equal("/api/auth/legacy-claim", fixture.Network.Requests[0].Path);
        Assert.Contains("legacy-proof", fixture.Network.Requests[0].Body);
        Assert.Equal(s_user, (await fixture.Auth.GetSessionAsync()).UserId);
        Assert.False(fixture.Credentials.Values.ContainsKey(CredentialKey.SupabaseSession));
        Assert.True(fixture.Credentials.Values.ContainsKey(CredentialKey.SideySession));
        Assert.Equal(s_user.ToString("D"), fixture.Credentials.Values[CredentialKey.LegacyClaimCompleted]);
        Assert.Equal(new[] { CredentialKey.SideySession, CredentialKey.LegacyClaimCompleted }, fixture.Credentials.Writes);
    }

    [Fact]
    public async Task ExistingWindowsLegacyPayloadGetsServerUserProofWithoutAnonymousSignup()
    {
        using var fixture = new Fixture();
        fixture.Credentials.Values[CredentialKey.SupabaseSession] = LegacyJson(knownAnonymous: null);
        fixture.Network.Reply($$"""{"id":"{{s_user}}","is_anonymous":true}""");
        fixture.Network.Reply(SessionJson());
        await fixture.Auth.AuthenticateAsync("GOOGLE", "provider-proof", "nonce");
        Assert.Equal("/auth/v1/user", fixture.Network.Requests[0].Path);
        Assert.Equal("legacy-proof", fixture.Network.Requests[0].Token);
        Assert.Equal("/api/auth/legacy-claim", fixture.Network.Requests[1].Path);
    }

    [Fact]
    public async Task ExpiredLegacyRefreshRemainsIsolatedFromNormalServiceCredentials()
    {
        using var fixture = new Fixture();
        fixture.Credentials.Values[CredentialKey.SupabaseSession] = LegacyJson(expired: true);
        fixture.Network.Reply($$$"""{"access_token":"fresh-legacy","refresh_token":"rotated-legacy","expires_in":3600,"user":{"id":"{{{s_user}}}","is_anonymous":true}}""");
        fixture.Network.Reply("{\"code\":\"identity_conflict\"}", HttpStatusCode.Conflict);
        await Assert.ThrowsAsync<SideyApiException>(() => fixture.Auth.AuthenticateAsync("GOOGLE", "other-proof", "nonce"));
        Assert.Equal("/auth/v1/token", fixture.Network.Requests[0].Path);
        Assert.Contains("fresh-legacy", fixture.Credentials.Values[CredentialKey.SupabaseSession]);
        Assert.False(fixture.Credentials.Values.ContainsKey(CredentialKey.SideySession));
        await Assert.ThrowsAsync<LegacyClaimRequiredException>(() => fixture.Auth.SendAsync(HttpMethod.Get, "rooms"));
        Assert.Equal(2, fixture.Network.Requests.Count);
    }

    [Fact]
    public async Task ChangedUuidOrFailedLocalPersistenceRetainsLegacyProof()
    {
        using var changed = new Fixture();
        changed.Credentials.Values[CredentialKey.SupabaseSession] = LegacyJson();
        changed.Network.Reply(SessionJson(user: Guid.NewGuid()));
        await Assert.ThrowsAsync<SessionRecoveryException>(() => changed.Auth.AuthenticateAsync("GOOGLE", "proof", "nonce"));
        Assert.True(changed.Credentials.Values.ContainsKey(CredentialKey.SupabaseSession));
        Assert.False(changed.Credentials.Values.ContainsKey(CredentialKey.SideySession));
        using var denied = new Fixture();
        denied.Credentials.Values[CredentialKey.SupabaseSession] = LegacyJson();
        denied.Credentials.RejectSideyWrite = true;
        denied.Network.Reply(SessionJson());
        await Assert.ThrowsAsync<IOException>(() => denied.Auth.AuthenticateAsync("GOOGLE", "proof", "nonce"));
        Assert.True(denied.Credentials.Values.ContainsKey(CredentialKey.SupabaseSession));
        Assert.False(denied.Credentials.Values.ContainsKey(CredentialKey.LegacyClaimCompleted));
    }

    [Fact]
    public async Task AdditionalProviderLinksAndLogoutRevokesBeforeLocalRemoval()
    {
        using var fixture = new Fixture();
        fixture.Credentials.Values[CredentialKey.SideySession] = SessionJson();
        fixture.Network.Reply("", HttpStatusCode.NoContent);
        fixture.Network.Reply("", HttpStatusCode.NoContent);
        await fixture.Auth.AuthenticateAsync("APPLE", "fresh-proof", "nonce");
        await fixture.Auth.SignOutAsync();
        Assert.Equal(["/api/auth/link", "/api/auth/logout"], fixture.Network.Requests.Select(request => request.Path));
        Assert.False(fixture.Credentials.Values.ContainsKey(CredentialKey.SideySession));
    }

    [Fact]
    public void GoogleDesktopProofUsesLoopbackS256AndRejectsDuplicateOrWrongState()
    {
        Uri url = GoogleDesktopOAuth.AuthorizationUri("installed-client", "backend-nonce",
            "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", "expected", new Uri("http://127.0.0.1:32123/"));
        Assert.Contains("code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", url.Query);
        Assert.Contains("code_challenge_method=S256", url.Query);
        Assert.Contains("nonce=backend-nonce", url.Query);
        Assert.Contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A32123%2F", url.Query);
        Assert.True(GoogleDesktopOAuth.TryParseCallback("GET /?code=valid&state=expected HTTP/1.1\r\n\r\n", "expected", out string? code, out _));
        Assert.Equal("valid", code);
        Assert.False(GoogleDesktopOAuth.TryParseCallback("GET /?code=valid&state=wrong HTTP/1.1\r\n\r\n", "expected", out _, out _));
        Assert.False(GoogleDesktopOAuth.TryParseCallback("GET /?code=valid&state=expected&state=expected HTTP/1.1\r\n\r\n", "expected", out _, out _));
    }

    [Fact]
    public async Task GoogleBrowserCallbackExchangesProofBeforeCreatingSideySession()
    {
        var credentials = new MemoryCredentials();
        var network = new RecordingNetwork();
        using var http = new HttpClient(network);
        using var browser = new HttpClient();
        using var auth = new SideyAuthService(s_configuration with { GoogleClientId = "installed-client" }, credentials, http, new FixedTime());
        network.Reply("{\"nonce\":\"server-nonce\"}");
        network.Reply("{\"id_token\":\"verified-provider-proof\"}");
        network.Reply(SessionJson());
        Task<HttpResponseMessage>? callback = null;
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));

        await auth.SignInWithGoogleAsync(url =>
        {
            var query = url.Query.TrimStart('?').Split('&')
                .Select(pair => pair.Split('=', 2))
                .ToDictionary(pair => pair[0], pair => Uri.UnescapeDataString(pair[1]));
            Assert.Equal("server-nonce", query["nonce"]);
            Assert.Equal("127.0.0.1", new Uri(query["redirect_uri"]).Host);
            callback = browser.GetAsync(query["redirect_uri"] + "?code=returned-code&state=" + Uri.EscapeDataString(query["state"]), timeout.Token);
            return Task.CompletedTask;
        }, timeout.Token);

        using HttpResponseMessage response = await callback!;
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(["/api/auth/challenge", "/token", "/api/auth/login"], network.Requests.Select(request => request.Path));
        Assert.Contains("code_verifier=", network.Requests[1].Body);
        Assert.Contains("returned-code", network.Requests[1].Body);
        Assert.Contains("verified-provider-proof", network.Requests[2].Body);
        Assert.Equal(s_user, (await auth.GetSessionAsync()).UserId);
    }

    [Theory]
    [InlineData("invalid_identity_credential")]
    [InlineData("identity_provider_unavailable")]
    [InlineData("auth_challenge_invalid")]
    public async Task InvalidFreshProviderProofDoesNotRotateOrReplayTheConsumedChallenge(string code)
    {
        using var fixture = new Fixture();
        fixture.Credentials.Values[CredentialKey.SideySession] = SessionJson();
        fixture.Network.Reply(JsonSerializer.Serialize(new { code }), HttpStatusCode.Unauthorized);
        await Assert.ThrowsAsync<SideyApiException>(() => fixture.Auth.UnlinkAsync("APPLE", "proof", "nonce"));
        Assert.Single(fixture.Network.Requests);
        Assert.Equal("/api/auth/unlink", fixture.Network.Requests[0].Path);
        Assert.Equal("access", (await fixture.Auth.GetSessionAsync()).AccessToken);
    }

    [Theory]
    [InlineData(HttpStatusCode.OK)]
    [InlineData(HttpStatusCode.Unauthorized)]
    public async Task LateOldAccountResponseCannotApplyOrReplayUnderNewAccount(HttpStatusCode lateStatus)
    {
        using var fixture = new Fixture();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        fixture.Credentials.Values[CredentialKey.SideySession] = SessionJson();
        fixture.Network.Reply("{}", lateStatus);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Network.ResponseGate = release.Task;
        Task<JsonElement> pending = fixture.Auth.SendAsync(HttpMethod.Post, "rooms", new { name = "old user room" }, deadline.Token);
        await fixture.Network.FirstRequest.Task.WaitAsync(deadline.Token);
        fixture.Network.ResponseGate = null;
        fixture.Network.Reply("", HttpStatusCode.NoContent);
        await fixture.Auth.SignOutAsync(deadline.Token);
        var newUser = Guid.NewGuid();
        fixture.Network.Reply(SessionJson(user: newUser, sid: Guid.NewGuid()));
        await fixture.Auth.AuthenticateAsync("GOOGLE", "new-proof", "new-nonce", deadline.Token);
        release.SetResult();
        await Assert.ThrowsAsync<AuthenticationRequiredException>(() => pending);
        Assert.Equal(newUser, (await fixture.Auth.GetSessionAsync(deadline.Token)).UserId);
        Assert.Equal(["/api/rooms", "/api/auth/logout", "/api/auth/login"], fixture.Network.Requests.Select(request => request.Path));
    }

    [Fact]
    public async Task LogoutAllAndAccountDeletionUseTheServerBeforeErasingCredentials()
    {
        using var all = new Fixture();
        all.Credentials.Values[CredentialKey.SideySession] = SessionJson();
        all.Network.Reply("", HttpStatusCode.NoContent);
        await all.Auth.SignOutAllAsync();
        Assert.Equal("/api/auth/logout-all", Assert.Single(all.Network.Requests).Path);
        Assert.False(all.Credentials.Values.ContainsKey(CredentialKey.SideySession));
        using var deletion = new Fixture();
        deletion.Credentials.Values[CredentialKey.SideySession] = SessionJson();
        deletion.Network.Reply("{\"code\":\"apple_reauthentication_required\"}", HttpStatusCode.BadRequest);
        await Assert.ThrowsAsync<SideyApiException>(() => deletion.Auth.DeleteAccountAsync());
        Assert.True(deletion.Credentials.Values.ContainsKey(CredentialKey.SideySession));
        deletion.Network.Reply("", HttpStatusCode.NoContent);
        await deletion.Auth.DeleteAppleAccountAsync(new AppleIdentityProof("fresh-token", "one-time-code"), "nonce");
        Assert.Equal("/api/account/apple", deletion.Network.Requests.Last().Path);
        Assert.Contains("one-time-code", deletion.Network.Requests.Last().Body);
        Assert.False(deletion.Credentials.Values.ContainsKey(CredentialKey.SideySession));
    }

    private static string SessionJson(string access = "access", string refresh = "refresh", bool expired = false, Guid? user = null, Guid? sid = null) =>
        JsonSerializer.Serialize(new SideySession(user ?? s_user, sid ?? s_sid, access, refresh,
            expired ? s_now.AddMinutes(-1) : s_now.AddMinutes(15)), s_json);

    private static string LegacyJson(bool expired = false, bool? knownAnonymous = true) => JsonSerializer.Serialize(new
    {
        accessToken = "legacy-proof",
        refreshToken = "legacy-refresh",
        userId = s_user,
        expiresAt = expired ? s_now.AddMinutes(-1) : s_now.AddMinutes(15),
        isAnonymous = knownAnonymous,
    }, s_json);

    private sealed class Fixture : IDisposable
    {
        public MemoryCredentials Credentials { get; } = new();
        public RecordingNetwork Network { get; } = new();
        public SideyAuthService Auth { get; }
        private readonly HttpClient _client;

        public Fixture()
        {
            _client = new HttpClient(Network);
            Auth = new SideyAuthService(s_configuration, Credentials, _client, new FixedTime());
        }

        public void Dispose()
        {
            Auth.Dispose();
            _client.Dispose();
        }
    }

    private sealed class FixedTime : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => s_now;
    }

    private sealed class MemoryCredentials : ICredentialStore
    {
        public Dictionary<CredentialKey, string> Values { get; } = [];
        public List<CredentialKey> Writes { get; } = [];
        public bool RejectSideyWrite { get; set; }

        public ValueTask<string?> ReadAsync(CredentialKey key, CancellationToken cancellationToken = default) =>
            ValueTask.FromResult(Values.GetValueOrDefault(key));

        public ValueTask WriteAsync(CredentialKey key, string value, CancellationToken cancellationToken = default)
        {
            if (RejectSideyWrite && key == CredentialKey.SideySession)
            {
                throw new IOException("Credential Manager denied access.");
            }

            Values[key] = value;
            Writes.Add(key);
            return ValueTask.CompletedTask;
        }

        public ValueTask DeleteAsync(CredentialKey key, CancellationToken cancellationToken = default)
        {
            Values.Remove(key);
            return ValueTask.CompletedTask;
        }

        public ValueTask<string?> ReadInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default) => ValueTask.FromResult<string?>(null);
        public ValueTask WriteInviteCodeAsync(Guid roomId, string inviteCode, CancellationToken cancellationToken = default) => ValueTask.CompletedTask;
        public ValueTask DeleteInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default) => ValueTask.CompletedTask;
    }

    private sealed record Request(string Path, string? Token, string Body);

    private sealed class RecordingNetwork : HttpMessageHandler
    {
        private readonly ConcurrentQueue<(string Body, HttpStatusCode Status)> _responses = new();
        public List<Request> Requests { get; } = [];
        public Task? ResponseGate { get; set; }
        public TaskCompletionSource FirstRequest { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public void Reply(string body, HttpStatusCode status = HttpStatusCode.OK) => _responses.Enqueue((body, status));

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            string body = request.Content is null ? string.Empty : await request.Content.ReadAsStringAsync(cancellationToken);
            Requests.Add(new Request(request.RequestUri!.AbsolutePath, request.Headers.Authorization?.Parameter, body));
            Assert.True(_responses.TryDequeue(out (string Body, HttpStatusCode Status) response));
            FirstRequest.TrySetResult();
            if (ResponseGate is { } gate)
            {
                await gate.WaitAsync(cancellationToken);
            }

            return new HttpResponseMessage(response.Status) { Content = new StringContent(response.Body, Encoding.UTF8, "application/json") };
        }
    }
}
