namespace Sidey.Platform.Windows.Authentication;

public static class WindowsAuthCallback
{
    public const string DevelopmentScheme = "sidey-dev";
    public const string ProductionScheme = "sidey";

    public static bool IsErrorCallback(string? activationArgument, string expectedScheme)
    {
        if (!Uri.TryCreate(activationArgument?.Trim(), UriKind.Absolute, out Uri? uri)
            || !StringComparer.OrdinalIgnoreCase.Equals(uri.Scheme, expectedScheme)
            || !StringComparer.OrdinalIgnoreCase.Equals(uri.Host, "auth")
            || uri.AbsolutePath != "/google" || !string.IsNullOrEmpty(uri.UserInfo)
            || (!string.IsNullOrEmpty(uri.Query) && !string.IsNullOrEmpty(uri.Fragment)))
            return false;
        string payload = string.IsNullOrEmpty(uri.Query) ? uri.Fragment.TrimStart('#') : uri.Query.TrimStart('?');
        if (payload.Length > 4096)
            return false;
        var keys = new HashSet<string>(StringComparer.Ordinal);
        foreach (string pair in payload.Split('&'))
        {
            string[] parts = pair.Split('=', 2);
            string key = Uri.UnescapeDataString(parts[0]);
            if (parts.Length != 2 || key is not ("error" or "error_code" or "error_description") || !keys.Add(key))
                return false;
        }
        return keys.Contains("error");
    }

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
