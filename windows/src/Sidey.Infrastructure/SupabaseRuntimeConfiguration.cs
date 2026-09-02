using System.Text;
using System.Text.Json;
using Sidey.Core.Localization;

namespace Sidey.Infrastructure;

public sealed record SupabaseRuntimeConfiguration(Uri Url, string PublishableKey)
{
    public const string ProductionHost = "whtejsviizgejauasqqt.supabase.co";
    public const string ProductionPublishableKey = "sb_publishable_kkASOI4rRTX8Drob21hkCw_VwUex63Y";

    public static SupabaseRuntimeConfiguration FromEnvironment()
    {
        var url = Environment.GetEnvironmentVariable("SIDEY_SUPABASE_URL")?.Trim();
        var key = Environment.GetEnvironmentVariable("SIDEY_SUPABASE_PUBLISHABLE_KEY")?.Trim();
        if (string.IsNullOrEmpty(url) && string.IsNullOrEmpty(key))
        {
            return new SupabaseRuntimeConfiguration(
                new Uri($"https://{ProductionHost}"),
                ProductionPublishableKey);
        }

        if (!Uri.TryCreate(url, UriKind.Absolute, out var parsed)
            || !IsAllowedBackend(parsed)
            || string.IsNullOrWhiteSpace(key)
            || LooksLikeSecretKey(key))
        {
            throw new InvalidOperationException(
                I18n.Get("backend.invalidOverride"));
        }

        return new SupabaseRuntimeConfiguration(parsed, key);
    }

    internal static bool IsAllowedBackend(Uri url) =>
        url.Scheme == Uri.UriSchemeHttps
        || (url.Scheme == Uri.UriSchemeHttp && url.IsLoopback);

    internal static bool LooksLikeSecretKey(string value)
    {
        if (value.StartsWith("sb_secret_", StringComparison.OrdinalIgnoreCase)
            || value.StartsWith("service_role", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        var parts = value.Split('.');
        if (parts.Length != 3)
        {
            return false;
        }

        try
        {
            var encoded = parts[1].Replace('-', '+').Replace('_', '/');
            encoded = encoded.PadRight(encoded.Length + ((4 - (encoded.Length % 4)) % 4), '=');
            using var document = JsonDocument.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(encoded)));
            return document.RootElement.TryGetProperty("role", out var role)
                && role.GetString() == "service_role";
        }
        catch (Exception exception) when (exception is FormatException or JsonException)
        {
            return false;
        }
    }
}
