using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Sidey.Infrastructure.Configuration;

public sealed record SideyRuntimeConfiguration(
    Uri ApiBaseUrl,
    string GoogleClientId = "",
    string GoogleClientSecret = "",
    Uri? LegacySupabaseUrl = null,
    string? LegacySupabasePublishableKey = null,
    string AppleServiceId = "",
    Uri? AppleRedirectUri = null)
{
    public const string ProductionHost = "api.sidey.app";
    public const string LegacyProductionHost = "whtejsviizgejauasqqt.supabase.co";
    public const string LegacyProductionPublishableKey = "sb_publishable_kkASOI4rRTX8Drob21hkCw_VwUex63Y";

    public Uri Url => ApiBaseUrl;
    public Uri LegacyUrl => LegacySupabaseUrl ?? new Uri($"https://{LegacyProductionHost}");
    public string LegacyPublishableKey => LegacySupabasePublishableKey ?? LegacyProductionPublishableKey;
    public string BackendFingerprint => Convert.ToHexStringLower(
        SHA256.HashData(Encoding.UTF8.GetBytes(ApiBaseUrl.AbsoluteUri.TrimEnd('/'))).AsSpan(0, 8));

    public static SideyRuntimeConfiguration FromEnvironment(IReadOnlyDictionary<string, string?>? environment = null)
    {
        string? Read(string key) => (environment is null
            ? Environment.GetEnvironmentVariable(key)
            : environment.GetValueOrDefault(key))?.Trim();
        string url = Read("SIDEY_API_BASE_URL") is { Length: > 0 } configured
            ? configured : $"https://{ProductionHost}/api";
        if (!Uri.TryCreate(url, UriKind.Absolute, out Uri? parsed) || !IsAllowedBackend(parsed))
        {
            throw new InvalidOperationException("SIDEY_API_BASE_URL must be HTTPS or loopback HTTP without credentials, query, or fragment.");
        }

        string? legacyUrl = Read("SIDEY_LEGACY_SUPABASE_URL");
        string? legacyKey = Read("SIDEY_LEGACY_SUPABASE_PUBLISHABLE_KEY");
        Uri? parsedLegacy = null;
        if (!string.IsNullOrEmpty(legacyUrl) || !string.IsNullOrEmpty(legacyKey))
        {
            if (!Uri.TryCreate(legacyUrl, UriKind.Absolute, out parsedLegacy)
                || !IsAllowedBackend(parsedLegacy) || string.IsNullOrWhiteSpace(legacyKey)
                || LooksLikeSecretKey(legacyKey))
            {
                throw new InvalidOperationException("Legacy ownership verification requires a safe URL and public key.");
            }
        }

        string? appleRedirect = Read("SIDEY_APPLE_REDIRECT_URI");
        if (!string.IsNullOrEmpty(appleRedirect) && (!Uri.TryCreate(appleRedirect, UriKind.Absolute, out Uri? validAppleRedirect)
            || !IsAllowedBackend(validAppleRedirect) || validAppleRedirect.Scheme != "https" || validAppleRedirect.IsLoopback))
            throw new InvalidOperationException("SIDEY_APPLE_REDIRECT_URI must be a registered HTTPS URL.");
        return new SideyRuntimeConfiguration(parsed, Read("SIDEY_GOOGLE_CLIENT_ID") ?? "",
            Read("SIDEY_GOOGLE_CLIENT_SECRET") ?? "", parsedLegacy, legacyKey,
            Read("SIDEY_APPLE_SERVICE_ID") ?? "", string.IsNullOrEmpty(appleRedirect) ? null : new Uri(appleRedirect));
    }

    internal static bool IsAllowedBackend(Uri url) =>
        url.IsAbsoluteUri && string.IsNullOrEmpty(url.UserInfo)
        && string.IsNullOrEmpty(url.Query) && string.IsNullOrEmpty(url.Fragment)
        && (url.Scheme == Uri.UriSchemeHttps || (url.Scheme == Uri.UriSchemeHttp && url.IsLoopback));

    internal static bool LooksLikeSecretKey(string value)
    {
        if (value.StartsWith("sb_secret_", StringComparison.OrdinalIgnoreCase)
            || value.StartsWith("service_role", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        string[] parts = value.Split('.');
        if (parts.Length != 3)
        {
            return false;
        }

        try
        {
            string encoded = parts[1].Replace('-', '+').Replace('_', '/');
            encoded = encoded.PadRight(encoded.Length + ((4 - (encoded.Length % 4)) % 4), '=');
            using var document = JsonDocument.Parse(Convert.FromBase64String(encoded));
            return document.RootElement.TryGetProperty("role", out JsonElement role)
                && role.GetString() == "service_role";
        }
        catch (Exception exception) when (exception is FormatException or JsonException)
        {
            return false;
        }
    }
}
