using Sidey.Core.Abstractions;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Sidey.Infrastructure;

internal interface IAuthSessionAccessor
{
    ValueTask<StoredSupabaseSession?> GetStoredSessionAsync(CancellationToken cancellationToken = default);
}

internal sealed record StoredSupabaseSession(
    string AccessToken,
    string RefreshToken,
    Guid UserId,
    DateTimeOffset ExpiresAt);

public sealed class SupabaseAnonymousAuthService : IAuthService, IAuthSessionAccessor, IDisposable
{
    private static readonly JsonSerializerOptions SerializerOptions = new(JsonSerializerDefaults.Web);

    private readonly SupabaseRuntimeConfiguration _configuration;
    private readonly ICredentialStore _credentials;
    private readonly HttpClient _httpClient;
    private readonly bool _ownsHttpClient;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public SupabaseAnonymousAuthService(
        SupabaseRuntimeConfiguration configuration,
        ICredentialStore credentials,
        HttpClient? httpClient = null)
    {
        _configuration = configuration ?? throw new ArgumentNullException(nameof(configuration));
        _credentials = credentials ?? throw new ArgumentNullException(nameof(credentials));
        _httpClient = httpClient ?? new HttpClient();
        _ownsHttpClient = httpClient is null;
    }

    public async Task<AuthSession?> RestoreSessionAsync(CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var stored = await RestoreStoredSessionWithinGateAsync(cancellationToken)
                .ConfigureAwait(false);
            return stored is null ? null : DomainSession(stored);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<AuthSession> CreateAnonymousSessionAsync(
        CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (await ReadStoredSessionAsync(cancellationToken).ConfigureAwait(false) is not null)
            {
                throw new InvalidOperationException(
                    "저장된 세션이 있는 설치에서는 익명 계정을 새로 만들 수 없습니다.");
            }

            var created = await RequestSessionAsync(
                HttpMethod.Post,
                "/auth/v1/signup",
                new { data = new { } },
                cancellationToken).ConfigureAwait(false);
            await StoreAsync(created, cancellationToken).ConfigureAwait(false);
            return DomainSession(created);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task SignOutAsync(CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var stored = await ReadStoredSessionAsync(cancellationToken).ConfigureAwait(false);
            if (stored is not null)
            {
                using var request = CreateRequest(HttpMethod.Post, "/auth/v1/logout", stored.AccessToken);
                using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
                _ = response.IsSuccessStatusCode;
            }

            await _credentials.DeleteAsync(CredentialKey.SupabaseSession, cancellationToken)
                .ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    async ValueTask<StoredSupabaseSession?> IAuthSessionAccessor.GetStoredSessionAsync(
        CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            return await RestoreStoredSessionWithinGateAsync(cancellationToken)
                .ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    public void Dispose()
    {
        _gate.Dispose();
        if (_ownsHttpClient)
        {
            _httpClient.Dispose();
        }
    }

    private async Task<StoredSupabaseSession> RequestSessionAsync(
        HttpMethod method,
        string relativePath,
        object body,
        CancellationToken cancellationToken)
    {
        using var request = CreateRequest(method, relativePath);
        request.Content = JsonContent.Create(body, options: SerializerOptions);
        using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException(
                $"Supabase 익명 인증 요청이 실패했습니다. HTTP {(int)response.StatusCode}.");
        }

        var envelope = await response.Content.ReadFromJsonAsync<AuthEnvelope>(
            SerializerOptions,
            cancellationToken).ConfigureAwait(false)
            ?? throw new InvalidDataException("Supabase 인증 응답이 비어 있습니다.");
        if (string.IsNullOrWhiteSpace(envelope.AccessToken)
            || string.IsNullOrWhiteSpace(envelope.RefreshToken)
            || envelope.User?.Id is not { } userId)
        {
            throw new InvalidDataException("Supabase 인증 응답에 필요한 세션 값이 없습니다.");
        }

        return new StoredSupabaseSession(
            envelope.AccessToken,
            envelope.RefreshToken,
            userId,
            DateTimeOffset.UtcNow.AddSeconds(Math.Max(60, envelope.ExpiresIn)));
    }

    private HttpRequestMessage CreateRequest(
        HttpMethod method,
        string relativePath,
        string? accessToken = null)
    {
        var request = new HttpRequestMessage(method, new Uri(_configuration.Url, relativePath));
        request.Headers.Add("apikey", _configuration.PublishableKey);
        if (!string.IsNullOrEmpty(accessToken))
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        }

        return request;
    }

    private async ValueTask<StoredSupabaseSession?> ReadStoredSessionAsync(
        CancellationToken cancellationToken)
    {
        var value = await _credentials.ReadAsync(CredentialKey.SupabaseSession, cancellationToken)
            .ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        try
        {
            return JsonSerializer.Deserialize<StoredSupabaseSession>(value, SerializerOptions)
                ?? throw new JsonException("Session payload was null.");
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException("저장된 SIDEY 세션을 해석할 수 없습니다.", exception);
        }
    }

    private async Task<StoredSupabaseSession?> RestoreStoredSessionWithinGateAsync(
        CancellationToken cancellationToken)
    {
        var stored = await ReadStoredSessionAsync(cancellationToken).ConfigureAwait(false);
        if (stored is null || stored.ExpiresAt > DateTimeOffset.UtcNow.AddMinutes(1))
        {
            return stored;
        }

        var refreshed = await RequestSessionAsync(
            HttpMethod.Post,
            "/auth/v1/token?grant_type=refresh_token",
            new { refresh_token = stored.RefreshToken },
            cancellationToken).ConfigureAwait(false);
        await StoreAsync(refreshed, cancellationToken).ConfigureAwait(false);
        return refreshed;
    }

    private async ValueTask StoreAsync(
        StoredSupabaseSession session,
        CancellationToken cancellationToken)
    {
        var value = JsonSerializer.Serialize(session, SerializerOptions);
        await _credentials.WriteAsync(CredentialKey.SupabaseSession, value, cancellationToken)
            .ConfigureAwait(false);
    }

    private static AuthSession DomainSession(StoredSupabaseSession session) =>
        new(session.UserId, session.ExpiresAt);

    private sealed record AuthEnvelope(
        [property: JsonPropertyName("access_token")] string? AccessToken,
        [property: JsonPropertyName("refresh_token")] string? RefreshToken,
        [property: JsonPropertyName("expires_in")] int ExpiresIn,
        [property: JsonPropertyName("user")] AuthUser? User);

    private sealed record AuthUser([property: JsonPropertyName("id")] Guid Id);
}
