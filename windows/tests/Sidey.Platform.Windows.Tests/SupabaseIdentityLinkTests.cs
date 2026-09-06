#if SIDEY_DEVELOPMENT_COMMERCE
using System.Net;
using System.Text;
using System.Text.Json;
using Sidey.Core.Abstractions;
using Sidey.Infrastructure;

namespace Sidey.Platform.Windows.Tests;

public sealed class SupabaseIdentityLinkTests
{
    [Fact]
    public async Task PkceIdentityLinkPreservesTheAnonymousUser()
    {
        Guid userId = Guid.NewGuid();
        var credentials = new MemoryCredentialStore(SessionJson(userId, "old-token"));
        var handler = new IdentityLinkHandler(userId);
        using var client = new HttpClient(handler);
        using var auth = new SupabaseAnonymousAuthService(
            new SupabaseRuntimeConfiguration(new Uri("https://staging.example.com"), "test-key"),
            credentials,
            client);

        Uri authorization = await auth.BeginGoogleIdentityLinkAsync(
            new Uri("sidey-dev://auth/google"));
        await auth.CompleteGoogleIdentityLinkAsync("returned-code");

        Assert.Equal("accounts.google.com", authorization.Host);
        Assert.Equal(2, handler.RequestCount);
        Assert.Contains("/auth/v1/user/identities/authorize", handler.AuthorizationRequestUri);
        Assert.Contains("provider=google", handler.AuthorizationRequestUri);
        Assert.Contains("redirect_to=sidey-dev%3A%2F%2Fauth%2Fgoogle", handler.AuthorizationRequestUri);
        Assert.Contains("code_challenge_method=s256", handler.AuthorizationRequestUri);
        Assert.DoesNotContain("code_verifier", handler.AuthorizationRequestUri);
        Assert.Contains("returned-code", handler.ExchangeBody);
        Assert.Contains("code_verifier", handler.ExchangeBody);
        Assert.Contains("new-token", credentials.SessionJson!);
    }

    [Fact]
    public async Task IdentityLinkRejectsAChangedUserWithoutReplacingTheStoredSession()
    {
        Guid originalUserId = Guid.NewGuid();
        string originalSession = SessionJson(originalUserId, "old-token");
        var credentials = new MemoryCredentialStore(originalSession);
        var handler = new IdentityLinkHandler(Guid.NewGuid());
        using var client = new HttpClient(handler);
        using var auth = new SupabaseAnonymousAuthService(
            new SupabaseRuntimeConfiguration(new Uri("https://staging.example.com"), "test-key"),
            credentials,
            client);
        _ = await auth.BeginGoogleIdentityLinkAsync(new Uri("sidey-dev://auth/google"));

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => auth.CompleteGoogleIdentityLinkAsync("returned-code"));

        Assert.Equal(originalSession, credentials.SessionJson);
    }

    private static string SessionJson(Guid userId, string accessToken) => JsonSerializer.Serialize(
        new StoredSupabaseSession(
            accessToken,
            "refresh-token",
            userId,
            DateTimeOffset.UtcNow.AddHours(1)),
        new JsonSerializerOptions(JsonSerializerDefaults.Web));

    private sealed class IdentityLinkHandler(Guid exchangeUserId) : HttpMessageHandler
    {
        public int RequestCount { get; private set; }
        public string AuthorizationRequestUri { get; private set; } = string.Empty;
        public string ExchangeBody { get; private set; } = string.Empty;

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestCount++;
            Assert.Equal("test-key", Assert.Single(request.Headers.GetValues("apikey")));
            if (RequestCount == 1)
            {
                Assert.Equal("old-token", request.Headers.Authorization?.Parameter);
                AuthorizationRequestUri = request.RequestUri?.AbsoluteUri ?? string.Empty;
                return JsonResponse("""{"url":"https://accounts.google.com/o/oauth2/v2/auth"}""");
            }

            Assert.Null(request.Headers.Authorization);
            ExchangeBody = await request.Content!.ReadAsStringAsync(cancellationToken);
            return JsonResponse($$"""
                {
                  "access_token": "new-token",
                  "refresh_token": "new-refresh-token",
                  "expires_in": 3600,
                  "user": { "id": "{{exchangeUserId}}" }
                }
                """);
        }

        private static HttpResponseMessage JsonResponse(string json) => new(HttpStatusCode.OK)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json"),
        };
    }

    private sealed class MemoryCredentialStore(string? sessionJson) : ICredentialStore
    {
        public string? SessionJson { get; private set; } = sessionJson;

        public ValueTask<string?> ReadAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default)
        {
            _ = key;
            _ = cancellationToken;
            return ValueTask.FromResult(SessionJson);
        }

        public ValueTask WriteAsync(
            CredentialKey key,
            string value,
            CancellationToken cancellationToken = default)
        {
            _ = key;
            _ = cancellationToken;
            SessionJson = value;
            return ValueTask.CompletedTask;
        }

        public ValueTask DeleteAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default)
        {
            _ = key;
            _ = cancellationToken;
            SessionJson = null;
            return ValueTask.CompletedTask;
        }

        public ValueTask<string?> ReadInviteCodeAsync(
            Guid roomId,
            CancellationToken cancellationToken = default)
        {
            _ = roomId;
            _ = cancellationToken;
            return ValueTask.FromResult<string?>(null);
        }

        public ValueTask WriteInviteCodeAsync(
            Guid roomId,
            string inviteCode,
            CancellationToken cancellationToken = default)
        {
            _ = roomId;
            _ = inviteCode;
            _ = cancellationToken;
            return ValueTask.CompletedTask;
        }

        public ValueTask DeleteInviteCodeAsync(
            Guid roomId,
            CancellationToken cancellationToken = default)
        {
            _ = roomId;
            _ = cancellationToken;
            return ValueTask.CompletedTask;
        }
    }
}
#endif
