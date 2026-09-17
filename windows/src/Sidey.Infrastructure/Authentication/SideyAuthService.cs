using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Sidey.Core.Abstractions;
using Sidey.Core.Localization;

namespace Sidey.Infrastructure.Authentication;

public sealed record SideySession(
    Guid UserId,
    Guid SessionId,
    string AccessToken,
    string RefreshToken,
    DateTimeOffset AccessExpiresAt)
{
    [JsonIgnore]
    public DateTimeOffset ExpiresAt => AccessExpiresAt;
}

public sealed class SideyApiException(string code, HttpStatusCode status)
    : HttpRequestException(SideyServiceError.Message(code), null, status)
{
    public string Code { get; } = code;
}

internal static class SideyServiceError
{
    public static string Message(string code) => I18n.Get(code switch
    {
        "identity_conflict" => "backend.identityConflict",
        "last_identity_unlink_forbidden" => "backend.lastIdentity",
        "membership_required" or "room_missing" or "target_membership_required" => "backend.membershipRequired",
        "rate_limited" or "invite_rate_limited" or "message_rate_limited" => "backend.rateLimited",
        "message_id_conflict" => "backend.messageConflict",
        "invalid_nickname" => "validation.nicknameLength",
        "invalid_room_name" => "validation.roomNameLength",
        "invalid_message" => "validation.messageLength",
        _ => "backend.requestFailed",
    });
}

/// <summary>Owns SIDEY service credentials; legacy Supabase credentials authorize only the one-time claim.</summary>
public sealed class SideyAuthService : IAuthService, IDisposable
{
    private static readonly JsonSerializerOptions s_json = new(JsonSerializerDefaults.Web);
    private readonly SideyRuntimeConfiguration _configuration;
    private readonly ICredentialStore _credentials;
    private readonly HttpClient _http;
    private readonly bool _ownsHttp;
    private readonly TimeProvider _time;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private SideySession? _session;
    private LegacySession? _legacy;
    private bool _loaded;
    private int _googleInFlight;

    public SideyAuthService(SideyRuntimeConfiguration configuration, ICredentialStore credentials,
        HttpClient? httpClient = null, TimeProvider? timeProvider = null)
    {
        _configuration = configuration ?? throw new ArgumentNullException(nameof(configuration));
        _credentials = credentials ?? throw new ArgumentNullException(nameof(credentials));
        _http = httpClient ?? new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
        _ownsHttp = httpClient is null;
        _time = timeProvider ?? TimeProvider.System;
    }

    public async Task<AuthSession?> RestoreSessionAsync(CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await LoadAsync(cancellationToken).ConfigureAwait(false);
            if (_session is null)
            {
                if (_legacy is not null)
                {
                    throw new LegacyClaimRequiredException();
                }

                return null;
            }

            SideySession session = await RequiredWithinGateAsync(cancellationToken).ConfigureAwait(false);
            return new AuthSession(session.UserId, session.ExpiresAt);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<SideySession> GetSessionAsync(CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            return await RequiredWithinGateAsync(cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<bool> HasLegacyCredentialAsync(CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await LoadAsync(cancellationToken).ConfigureAwait(false);
            return _legacy is not null;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<string> ChallengeAsync(CancellationToken cancellationToken = default)
    {
        JsonElement result = await RequestAsync(HttpMethod.Post, ApiUri("auth/challenge"), new { }, null, cancellationToken)
            .ConfigureAwait(false);
        return result.TryGetProperty("nonce", out JsonElement nonce) && nonce.GetString() is { Length: > 0 } value
            ? value : throw new InvalidDataException("SIDEY challenge was missing.");
    }

    public async Task AuthenticateAsync(string provider, string credential, string nonce,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(provider);
        ArgumentException.ThrowIfNullOrWhiteSpace(credential);
        ArgumentException.ThrowIfNullOrWhiteSpace(nonce);
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await LoadAsync(cancellationToken).ConfigureAwait(false);
            var proof = new Dictionary<string, string>
            {
                ["provider"] = provider,
                ["credential"] = credential,
                ["nonce"] = nonce,
                ["platform"] = "WINDOWS",
            };
            if (_session is not null)
            {
                SideySession current = await RequiredWithinGateAsync(cancellationToken).ConfigureAwait(false);
                _ = await RequestAsync(HttpMethod.Post, ApiUri("auth/link"), proof, current.AccessToken, cancellationToken)
                    .ConfigureAwait(false);
                return;
            }

            Guid? expectedUser = null;
            string path = "auth/login";
            if (_legacy is not null)
            {
                LegacySession legacy = await LegacyProofAsync(cancellationToken).ConfigureAwait(false);
                expectedUser = legacy.UserId;
                if (legacy.IsAnonymous == true)
                {
                    path = "auth/legacy-claim";
                    proof["legacyCredential"] = legacy.AccessToken;
                }
            }

            JsonElement response = await RequestAsync(HttpMethod.Post, ApiUri(path), proof, null, cancellationToken)
                .ConfigureAwait(false);
            SideySession next = DecodeSession(response);
            if (expectedUser is { } original && next.UserId != original)
            {
                throw new SessionRecoveryException("Provider login did not return the original SIDEY account.");
            }

            await StoreAsync(next, cancellationToken).ConfigureAwait(false);
            if (_legacy is not null)
            {
                // The new credentials must be safely stored before old proof is removed.
                await _credentials.WriteAsync(CredentialKey.LegacyClaimCompleted, next.UserId.ToString("D"), cancellationToken)
                    .ConfigureAwait(false);
                await _credentials.DeleteAsync(CredentialKey.SupabaseSession, cancellationToken).ConfigureAwait(false);
                _legacy = null;
            }
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task SignInWithGoogleAsync(Func<Uri, Task> openBrowser, CancellationToken cancellationToken = default)
        => await GoogleProofAsync(openBrowser, unlink: false, cancellationToken).ConfigureAwait(false);

    public async Task UnlinkGoogleAsync(Func<Uri, Task> openBrowser, CancellationToken cancellationToken = default)
        => await GoogleProofAsync(openBrowser, unlink: true, cancellationToken).ConfigureAwait(false);

    public async Task UnlinkAsync(string provider, string credential, string nonce, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(credential);
        ArgumentException.ThrowIfNullOrWhiteSpace(nonce);
        _ = await SendAsync(HttpMethod.Post, "auth/unlink", new { provider, credential, nonce }, cancellationToken)
            .ConfigureAwait(false);
    }

    private async Task GoogleProofAsync(Func<Uri, Task> openBrowser, bool unlink, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(openBrowser);
        if (string.IsNullOrWhiteSpace(_configuration.GoogleClientId))
        {
            throw new InvalidOperationException("SIDEY_GOOGLE_CLIENT_ID must configure a Google installed-desktop OAuth client.");
        }

        if (Interlocked.CompareExchange(ref _googleInFlight, 1, 0) != 0)
        {
            throw new InvalidOperationException("An authentication request is already in progress.");
        }

        try
        {
            string nonce = await ChallengeAsync(cancellationToken).ConfigureAwait(false);
            string proof = await GoogleDesktopOAuth.AuthenticateAsync(_configuration, nonce, openBrowser, _http, cancellationToken)
                .ConfigureAwait(false);
            if (unlink)
                await UnlinkAsync("GOOGLE", proof, nonce, cancellationToken).ConfigureAwait(false);
            else
                await AuthenticateAsync("GOOGLE", proof, nonce, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            Volatile.Write(ref _googleInFlight, 0);
        }
    }

    public Task SignOutAsync(CancellationToken cancellationToken = default) => EndSessionAsync("auth/logout", cancellationToken);

    public Task SignOutAllAsync(CancellationToken cancellationToken = default) => EndSessionAsync("auth/logout-all", cancellationToken);

    public async Task DeleteAccountAsync(CancellationToken cancellationToken = default)
    {
        _ = await SendAsync(HttpMethod.Delete, "account", cancellationToken: cancellationToken).ConfigureAwait(false);
        await ForgetSessionAsync().ConfigureAwait(false);
    }

    public async Task DeleteAppleAccountAsync(AppleIdentityProof proof, string nonce, CancellationToken cancellationToken = default)
    {
        _ = await SendAsync(HttpMethod.Delete, "account/apple", new
        {
            identityToken = proof.IdentityToken,
            nonce,
            authorizationCode = proof.AuthorizationCode,
        }, cancellationToken).ConfigureAwait(false);
        await ForgetSessionAsync().ConfigureAwait(false);
    }

    private async Task ForgetSessionAsync()
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            _session = null;
            await _credentials.DeleteAsync(CredentialKey.SideySession, CancellationToken.None).ConfigureAwait(false);
        }
        finally { _gate.Release(); }
    }

    private async Task EndSessionAsync(string path, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await LoadAsync(cancellationToken).ConfigureAwait(false);
            if (_session is not null)
            {
                try
                {
                    SideySession current = await RequiredWithinGateAsync(cancellationToken).ConfigureAwait(false);
                    _ = await RequestAsync(HttpMethod.Post, ApiUri(path), new { }, current.AccessToken, cancellationToken)
                        .ConfigureAwait(false);
                }
                catch (AuthenticationRequiredException) { /* The server session is already unusable. */ }
            }

            _session = null;
            await _credentials.DeleteAsync(CredentialKey.SideySession, CancellationToken.None).ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<JsonElement> SendAsync(HttpMethod method, string relativeApiPath, object? body = null,
        CancellationToken cancellationToken = default)
    {
        Uri uri = ApiUri(relativeApiPath);
        SideySession current = await GetSessionAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            JsonElement response = await RequestAsync(method, uri, body, current.AccessToken, cancellationToken).ConfigureAwait(false);
            await CheckSessionAsync(current.SessionId, cancellationToken).ConfigureAwait(false);
            return response;
        }
        catch (SideyApiException exception) when (exception.StatusCode == HttpStatusCode.Unauthorized
            && exception.Code is "http_401" or "session_rejected")
        {
            // Replay only an explicitly unauthorized request, never an uncertain transport failure.
            await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                if (_session is null || _session.SessionId != current.SessionId)
                {
                    throw new AuthenticationRequiredException();
                }

                if (_session.AccessToken == current.AccessToken)
                {
                    _ = await RotateAsync(_session, cancellationToken).ConfigureAwait(false);
                }

                current = _session;
            }
            finally
            {
                _gate.Release();
            }

            JsonElement response = await RequestAsync(method, uri, body, current.AccessToken, cancellationToken).ConfigureAwait(false);
            await CheckSessionAsync(current.SessionId, cancellationToken).ConfigureAwait(false);
            return response;
        }
    }

    private async Task CheckSessionAsync(Guid expectedSession, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (_session?.SessionId != expectedSession)
                throw new AuthenticationRequiredException();
        }
        finally { _gate.Release(); }
    }

    private async Task LoadAsync(CancellationToken cancellationToken)
    {
        if (_loaded)
        {
            return;
        }

        string? stored = await _credentials.ReadAsync(CredentialKey.SideySession, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(stored))
        {
            using var json = JsonDocument.Parse(stored);
            _session = DecodeSession(json.RootElement);
        }

        if (_session is null && await _credentials.ReadAsync(CredentialKey.LegacyClaimCompleted, cancellationToken)
            .ConfigureAwait(false) is null)
        {
            string? old = await _credentials.ReadAsync(CredentialKey.SupabaseSession, cancellationToken).ConfigureAwait(false);
            if (!string.IsNullOrWhiteSpace(old))
            {
                _legacy = JsonSerializer.Deserialize<LegacySession>(old, s_json)
                    ?? throw new SessionRecoveryException("The legacy credential could not be decoded.");
                if (_legacy.UserId == Guid.Empty || string.IsNullOrWhiteSpace(_legacy.RefreshToken))
                {
                    throw new SessionRecoveryException("The legacy ownership credential is incomplete.");
                }
            }
        }

        _loaded = true;
    }

    private async Task<SideySession> RequiredWithinGateAsync(CancellationToken cancellationToken)
    {
        await LoadAsync(cancellationToken).ConfigureAwait(false);
        if (_session is null)
        {
            throw _legacy is null ? new AuthenticationRequiredException() : new LegacyClaimRequiredException();
        }

        return _session.ExpiresAt > _time.GetUtcNow().AddSeconds(30)
            ? _session : await RotateAsync(_session, cancellationToken).ConfigureAwait(false);
    }

    private async Task<SideySession> RotateAsync(SideySession current, CancellationToken cancellationToken)
    {
        SideySession next;
        try
        {
            JsonElement result = await RequestAsync(HttpMethod.Post, ApiUri("auth/refresh"),
                new { refreshToken = current.RefreshToken }, null, cancellationToken).ConfigureAwait(false);
            next = DecodeSession(result);
            if (next.UserId != current.UserId || next.SessionId != current.SessionId)
            {
                throw new InvalidDataException("The rotated session changed identity.");
            }
        }
        catch (Exception exception) when (exception is HttpRequestException or JsonException or InvalidDataException or OperationCanceledException)
        {
            // If the response was lost after commit, the old token may already
            // be consumed. Never replay it: a fresh provider proof is required.
            _session = null;
            await _credentials.DeleteAsync(CredentialKey.SideySession, CancellationToken.None).ConfigureAwait(false);
            throw new AuthenticationRequiredException("세션을 다시 인증해 주세요.", exception);
        }

        try
        {
            await StoreAsync(next, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception error)
        {
            // The server consumed the old refresh token. A failed secure write must
            // not leave that credential eligible for another rotation.
            _session = null;
            await _credentials.DeleteAsync(CredentialKey.SideySession, CancellationToken.None).ConfigureAwait(false);
            throw new AuthenticationRequiredException("세션을 다시 인증해 주세요.", error);
        }
        return next;
    }

    private async Task StoreAsync(SideySession session, CancellationToken cancellationToken)
    {
        await _credentials.WriteAsync(CredentialKey.SideySession, JsonSerializer.Serialize(session, s_json), cancellationToken)
            .ConfigureAwait(false);
        _session = session;
    }

    private async Task<LegacySession> LegacyProofAsync(CancellationToken cancellationToken)
    {
        LegacySession current = _legacy ?? throw new LegacyClaimRequiredException();
        if (current.ExpiresAt <= _time.GetUtcNow().AddSeconds(60))
        {
            JsonElement response = await RequestAsync(HttpMethod.Post,
                new Uri(_configuration.LegacyUrl, "/auth/v1/token?grant_type=refresh_token"),
                new { refresh_token = current.RefreshToken }, null, cancellationToken, legacy: true).ConfigureAwait(false);
            JsonElement user = response.GetProperty("user");
            Guid id = user.GetProperty("id").GetGuid();
            if (id != current.UserId)
            {
                throw new SessionRecoveryException("The legacy ownership credential changed identity.");
            }

            current = new LegacySession(response.GetProperty("access_token").GetString()!,
                response.GetProperty("refresh_token").GetString()!, id,
                _time.GetUtcNow().AddSeconds(response.GetProperty("expires_in").GetInt32()),
                user.GetProperty("is_anonymous").GetBoolean());
            await StoreLegacyAsync(current, cancellationToken).ConfigureAwait(false);
        }
        else if (current.IsAnonymous is null)
        {
            JsonElement user = await RequestAsync(HttpMethod.Get, new Uri(_configuration.LegacyUrl, "/auth/v1/user"),
                null, current.AccessToken, cancellationToken, legacy: true).ConfigureAwait(false);
            if (user.GetProperty("id").GetGuid() != current.UserId)
            {
                throw new SessionRecoveryException("The legacy ownership credential changed identity.");
            }

            current = current with { IsAnonymous = user.GetProperty("is_anonymous").GetBoolean() };
            await StoreLegacyAsync(current, cancellationToken).ConfigureAwait(false);
        }

        return current;
    }

    private async Task StoreLegacyAsync(LegacySession value, CancellationToken cancellationToken)
    {
        await _credentials.WriteAsync(CredentialKey.SupabaseSession, JsonSerializer.Serialize(value, s_json), cancellationToken)
            .ConfigureAwait(false);
        _legacy = value;
    }

    private Uri ApiUri(string path)
    {
        ArgumentNullException.ThrowIfNull(path);
        if (path.StartsWith("//", StringComparison.Ordinal) || path.Contains("://", StringComparison.Ordinal)
            || path.Split('/').Contains("..", StringComparer.Ordinal))
        {
            throw new ArgumentException("An API-relative path is required.", nameof(path));
        }

        var baseUri = new Uri(_configuration.ApiBaseUrl.AbsoluteUri.TrimEnd('/') + "/");
        var result = new Uri(baseUri, path.TrimStart('/'));
        if (result.Scheme != baseUri.Scheme || result.Authority != baseUri.Authority)
        {
            throw new ArgumentException("The API origin cannot be changed.", nameof(path));
        }

        return result;
    }

    private async Task<JsonElement> RequestAsync(HttpMethod method, Uri uri, object? body, string? token,
        CancellationToken cancellationToken, bool legacy = false)
    {
        using var request = new HttpRequestMessage(method, uri);
        if (body is not null)
        {
            request.Content = JsonContent.Create(body, options: s_json);
        }

        if (token is not null)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }

        if (legacy)
        {
            request.Headers.Add("apikey", _configuration.LegacyPublishableKey);
        }

        using HttpResponseMessage response = await _http.SendAsync(request, cancellationToken).ConfigureAwait(false);
        string text = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            string code = $"http_{(int)response.StatusCode}";
            try
            {
                using var error = JsonDocument.Parse(text);
                if (error.RootElement.TryGetProperty("code", out JsonElement value) && value.GetString() is { } parsed)
                {
                    code = parsed;
                }
            }
            catch (JsonException)
            {
                // Do not put potentially sensitive provider response bodies into errors or logs.
            }

            throw new SideyApiException(code, response.StatusCode);
        }

        using var result = JsonDocument.Parse(string.IsNullOrWhiteSpace(text) ? "{}" : text);
        return result.RootElement.Clone();
    }

    private static SideySession DecodeSession(JsonElement json)
    {
        SideySession session = json.Deserialize<SideySession>(s_json)
            ?? throw new InvalidDataException("The SIDEY session was missing.");
        if (session.UserId == Guid.Empty || session.SessionId == Guid.Empty
            || string.IsNullOrWhiteSpace(session.AccessToken) || string.IsNullOrWhiteSpace(session.RefreshToken)
            || session.AccessExpiresAt == default)
        {
            throw new InvalidDataException("The SIDEY session was incomplete.");
        }

        return session;
    }

    public void Dispose()
    {
        _gate.Dispose();
        if (_ownsHttp)
        {
            _http.Dispose();
        }
    }

    private sealed record LegacySession(string AccessToken, string RefreshToken, Guid UserId,
        DateTimeOffset ExpiresAt, bool? IsAnonymous = null);
}
