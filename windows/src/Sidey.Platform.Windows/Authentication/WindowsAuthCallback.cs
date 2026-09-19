namespace Sidey.Platform.Windows.Authentication;

public static class WindowsAuthCallback
{
    public const string DevelopmentScheme = "sidey-dev";
    public const string ProductionScheme = "sidey";

    private static readonly HashSet<string> s_errorKeys =
    [
        "error",
        "error_code",
        "error_description",
    ];

    public static bool IsErrorCallback(string? activationArgument, string expectedScheme) =>
        TryGetError(activationArgument, expectedScheme, out _, out _);

    public static bool TryGetError(
        string? activationArgument,
        string expectedScheme,
        out string? error,
        out string? errorCode)
    {
        error = null;
        errorCode = null;
        if (!Uri.TryCreate(activationArgument?.Trim(), UriKind.Absolute, out Uri? uri)
            || !StringComparer.OrdinalIgnoreCase.Equals(uri.Scheme, expectedScheme)
            || !StringComparer.OrdinalIgnoreCase.Equals(uri.Host, "auth")
            || uri.AbsolutePath != "/google" || !string.IsNullOrEmpty(uri.UserInfo)
            || uri.Query.Length > 8192 || uri.Fragment.Length > 8192)
        {
            return false;
        }

        if (!TryParseErrorPayload(uri.Query.TrimStart('?'), allowSupabaseMarker: false, out Dictionary<string, string> query)
            || !TryParseErrorPayload(uri.Fragment.TrimStart('#'), allowSupabaseMarker: true, out Dictionary<string, string> fragment)
            || (query.Count == 0 && fragment.Count == 0)
            || !PayloadsAgree(query, fragment))
        {
            return false;
        }

        error = Value(query, fragment, "error");
        errorCode = Value(query, fragment, "error_code");
        return IsDiagnosticToken(error) && (errorCode is null || IsDiagnosticToken(errorCode));
    }

    private static bool TryParseErrorPayload(
        string payload,
        bool allowSupabaseMarker,
        out Dictionary<string, string> values)
    {
        values = new Dictionary<string, string>(StringComparer.Ordinal);
        if (string.IsNullOrEmpty(payload))
        {
            return true;
        }

        try
        {
            bool supabaseMarkerSeen = false;
            foreach (string pair in payload.Split('&', StringSplitOptions.RemoveEmptyEntries))
            {
                string[] parts = pair.Split('=', 2);
                if (parts.Length != 2)
                {
                    return false;
                }

                string key = Uri.UnescapeDataString(parts[0].Replace('+', ' '));
                string value = Uri.UnescapeDataString(parts[1].Replace('+', ' '));
                if (key == "sb" && allowSupabaseMarker && value.Length == 0)
                {
                    if (supabaseMarkerSeen)
                    {
                        return false;
                    }
                    supabaseMarkerSeen = true;
                    continue;
                }
                if (!s_errorKeys.Contains(key) || value.Length > 4096 || !values.TryAdd(key, value))
                {
                    return false;
                }
            }
        }
        catch (UriFormatException)
        {
            return false;
        }

        return true;
    }

    private static bool PayloadsAgree(
        IReadOnlyDictionary<string, string> query,
        IReadOnlyDictionary<string, string> fragment)
    {
        if (query.Count == 0 || fragment.Count == 0)
        {
            return true;
        }
        if (query.Count != fragment.Count)
        {
            return false;
        }

        foreach ((string key, string value) in fragment)
        {
            if (!query.TryGetValue(key, out string? queryValue)
                || !StringComparer.Ordinal.Equals(value, queryValue))
            {
                return false;
            }
        }

        return true;
    }

    private static string? Value(
        IReadOnlyDictionary<string, string> query,
        IReadOnlyDictionary<string, string> fragment,
        string key) =>
        query.TryGetValue(key, out string? queryValue)
            ? queryValue
            : fragment.TryGetValue(key, out string? fragmentValue) ? fragmentValue : null;

    private static bool IsDiagnosticToken(string? value) =>
        !string.IsNullOrWhiteSpace(value)
        && value.Length <= 128
        && value.All(character => char.IsAsciiLetterOrDigit(character) || character is '_' or '-');

    public static bool TryGetCode(
        string? activationArgument,
        string expectedScheme,
        out Uri? callbackUri,
        out string? code)
    {
        callbackUri = null;
        code = null;
        if (string.IsNullOrWhiteSpace(activationArgument)
            || !Uri.TryCreate(activationArgument.Trim(), UriKind.Absolute, out Uri? parsed)
            || !StringComparer.OrdinalIgnoreCase.Equals(parsed.Scheme, expectedScheme)
            || !StringComparer.OrdinalIgnoreCase.Equals(parsed.Host, "auth")
            || !StringComparer.Ordinal.Equals(parsed.AbsolutePath, "/google")
            || !string.IsNullOrEmpty(parsed.Fragment)
            || !string.IsNullOrEmpty(parsed.UserInfo))
        {
            return false;
        }

        string[] pairs = parsed.Query.TrimStart('?').Split(
            '&',
            StringSplitOptions.RemoveEmptyEntries);
        if (pairs.Length != 1)
        {
            return false;
        }
        string[] parts = pairs[0].Split('=', 2);
        if (parts.Length != 2
            || !StringComparer.Ordinal.Equals(
                Uri.UnescapeDataString(parts[0].Replace('+', ' ')),
                "code"))
        {
            return false;
        }
        string candidate = Uri.UnescapeDataString(parts[1].Replace('+', ' '));
        if (string.IsNullOrWhiteSpace(candidate) || candidate.Length > 2048)
        {
            return false;
        }

        callbackUri = parsed;
        code = candidate;
        return true;
    }
}
