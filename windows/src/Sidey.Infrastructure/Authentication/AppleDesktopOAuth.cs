using System.Security.Cryptography;
using System.Text;
using Sidey.Core.Abstractions;

namespace Sidey.Infrastructure.Authentication;

public sealed record AppleIdentityProof(string IdentityToken, string AuthorizationCode);

/// <summary>Apple's no-scope hybrid flow returns proof in the redirect fragment, never to the callback host.</summary>
public sealed class AppleDesktopOAuth
{
    public Uri AuthorizationUri { get; }
    public Uri RedirectUri { get; }
    private readonly string _state;

    public AppleDesktopOAuth(SideyRuntimeConfiguration configuration, string nonce)
    {
        if (string.IsNullOrWhiteSpace(configuration.AppleServiceId)
            || configuration.AppleRedirectUri is not { Scheme: "https" } redirect
            || !string.IsNullOrEmpty(redirect.Query) || !string.IsNullOrEmpty(redirect.Fragment)
            || !string.IsNullOrEmpty(redirect.UserInfo) || redirect.IsLoopback)
            throw new InvalidOperationException("Configure SIDEY_APPLE_SERVICE_ID and a registered HTTPS SIDEY_APPLE_REDIRECT_URI.");
        ArgumentException.ThrowIfNullOrWhiteSpace(nonce);
        RedirectUri = redirect;
        _state = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(32));
        Dictionary<string, string> query = new()
        {
            ["client_id"] = configuration.AppleServiceId,
            ["redirect_uri"] = redirect.AbsoluteUri,
            ["response_type"] = "code id_token",
            ["response_mode"] = "fragment",
            ["state"] = _state,
            ["nonce"] = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(nonce))),
        };
        AuthorizationUri = new Uri("https://appleid.apple.com/auth/authorize?" + string.Join('&',
            query.Select(pair => $"{Uri.EscapeDataString(pair.Key)}={Uri.EscapeDataString(pair.Value)}")));
    }

    public bool IsCallback(Uri uri) => uri.Scheme == RedirectUri.Scheme
        && uri.IdnHost == RedirectUri.IdnHost && uri.Port == RedirectUri.Port
        && uri.AbsolutePath == RedirectUri.AbsolutePath && string.IsNullOrEmpty(uri.UserInfo);

    public AppleIdentityProof Complete(Uri callback)
    {
        if (!IsCallback(callback) || !string.IsNullOrEmpty(callback.Query) || callback.Fragment.Length > 32768)
            throw new AuthenticationRequiredException("Invalid Apple callback.");
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (string component in callback.Fragment.TrimStart('#').Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            string[] pair = component.Split('=', 2);
            if (pair.Length != 2 || !values.TryAdd(Uri.UnescapeDataString(pair[0]), Uri.UnescapeDataString(pair[1])))
                throw new AuthenticationRequiredException("Invalid Apple callback.");
        }
        if (!values.TryGetValue("state", out string? state)
            || !CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(state), Encoding.UTF8.GetBytes(_state)))
            throw new AuthenticationRequiredException("Invalid Apple callback state.");
        if (values.ContainsKey("error"))
            throw new OperationCanceledException("Apple sign-in was canceled.");
        if (!values.TryGetValue("id_token", out string? token) || string.IsNullOrWhiteSpace(token)
            || token.Length > 16384 || !values.TryGetValue("code", out string? code) || string.IsNullOrWhiteSpace(code))
            throw new AuthenticationRequiredException("Apple identity proof was missing.");
        return new AppleIdentityProof(token, code);
    }
}
