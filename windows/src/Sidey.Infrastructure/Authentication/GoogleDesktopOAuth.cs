using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Sidey.Core.Abstractions;

namespace Sidey.Infrastructure.Authentication;

/// <summary>Google installed-desktop OAuth: browser + loopback callback + S256 PKCE, without a custom redirect scheme.</summary>
internal static class GoogleDesktopOAuth
{
    public static async Task<string> AuthenticateAsync(SideyRuntimeConfiguration configuration, string nonce,
        Func<Uri, Task> openBrowser, HttpClient http, CancellationToken cancellationToken)
    {
        string verifier = Base64Url(RandomNumberGenerator.GetBytes(32));
        string state = Base64Url(RandomNumberGenerator.GetBytes(32));
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromMinutes(3));
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start(4);
        try
        {
            int port = ((IPEndPoint)listener.LocalEndpoint).Port;
            var redirect = new Uri($"http://127.0.0.1:{port}/");
            await openBrowser(AuthorizationUri(configuration.GoogleClientId, nonce, verifier, state, redirect))
                .ConfigureAwait(false);
            string code = await ReceiveCodeAsync(listener, state, timeout.Token).ConfigureAwait(false);
            var fields = new Dictionary<string, string>
            {
                ["client_id"] = configuration.GoogleClientId,
                ["code"] = code,
                ["code_verifier"] = verifier,
                ["redirect_uri"] = redirect.AbsoluteUri,
                ["grant_type"] = "authorization_code",
            };
            if (!string.IsNullOrEmpty(configuration.GoogleClientSecret))
            {
                fields["client_secret"] = configuration.GoogleClientSecret;
            }

            using var request = new HttpRequestMessage(HttpMethod.Post, "https://oauth2.googleapis.com/token")
            {
                Content = new FormUrlEncodedContent(fields),
            };
            using HttpResponseMessage response = await http.SendAsync(request, timeout.Token).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                throw new AuthenticationRequiredException("Google 인증 코드를 확인하지 못했습니다.");
            }

            await using Stream content = await response.Content.ReadAsStreamAsync(timeout.Token).ConfigureAwait(false);
            using JsonDocument json = await JsonDocument.ParseAsync(content, cancellationToken: timeout.Token).ConfigureAwait(false);
            return json.RootElement.TryGetProperty("id_token", out JsonElement token) && token.GetString() is { Length: > 0 } value
                ? value : throw new AuthenticationRequiredException("Google identity token이 없습니다.");
        }
        finally
        {
            listener.Stop();
        }
    }

    internal static Uri AuthorizationUri(string clientId, string nonce, string verifier, string state, Uri redirect)
    {
        var values = new Dictionary<string, string>
        {
            ["client_id"] = clientId,
            ["response_type"] = "code",
            ["redirect_uri"] = redirect.AbsoluteUri,
            ["scope"] = "openid email",
            ["state"] = state,
            ["nonce"] = nonce,
            ["code_challenge"] = Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier))),
            ["code_challenge_method"] = "S256",
            ["prompt"] = "select_account",
        };
        string query = string.Join('&', values.Select(pair => $"{Uri.EscapeDataString(pair.Key)}={Uri.EscapeDataString(pair.Value)}"));
        return new Uri($"https://accounts.google.com/o/oauth2/v2/auth?{query}");
    }

    private static async Task<string> ReceiveCodeAsync(TcpListener listener, string state, CancellationToken cancellationToken)
    {
        while (true)
        {
            using TcpClient client = await listener.AcceptTcpClientAsync(cancellationToken).ConfigureAwait(false);
            using var requestTimeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            requestTimeout.CancelAfter(TimeSpan.FromSeconds(5));
            await using NetworkStream stream = client.GetStream();
            try
            {
                byte[] buffer = new byte[8192];
                int length = 0;
                while (length < buffer.Length)
                {
                    int read = await stream.ReadAsync(buffer.AsMemory(length), requestTimeout.Token).ConfigureAwait(false);
                    if (read == 0)
                    {
                        break;
                    }

                    length += read;
                    string request = Encoding.ASCII.GetString(buffer, 0, length);
                    if (!request.Contains("\r\n\r\n", StringComparison.Ordinal))
                    {
                        continue;
                    }

                    bool valid = TryParseCallback(request, state, out string? code, out bool denied);
                    string body = valid ? "SIDEY login received. You can close this window." : "Invalid login callback.";
                    byte[] response = Encoding.ASCII.GetBytes($"HTTP/1.1 {(valid ? "200 OK" : "400 Bad Request")}\r\nContent-Type: text/plain\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n{body}");
                    await stream.WriteAsync(response, requestTimeout.Token).ConfigureAwait(false);
                    if (denied)
                    {
                        throw new AuthenticationRequiredException("Google 로그인이 취소되었습니다.");
                    }

                    if (valid && code is not null)
                    {
                        return code;
                    }

                    break;
                }
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                // A stalled local connection cannot keep the callback open indefinitely.
            }
            catch (IOException)
            {
                // Unrelated local probes do not end an authenticated browser flow.
            }
        }
    }

    internal static bool TryParseCallback(string request, string expectedState, out string? code, out bool denied)
    {
        code = null;
        denied = false;
        string[] first = request.Split("\r\n", 2, StringSplitOptions.None)[0].Split(' ');
        if (first.Length != 3 || first[0] != "GET" || !first[1].StartsWith("/?", StringComparison.Ordinal)
            || !Uri.TryCreate("http://127.0.0.1" + first[1], UriKind.Absolute, out Uri? uri) || uri.AbsolutePath != "/")
        {
            return false;
        }

        var query = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (string pair in uri.Query.TrimStart('?').Split('&'))
        {
            string[] parts = pair.Split('=', 2);
            string key = Uri.UnescapeDataString(parts[0]);
            string value = parts.Length == 2 ? Uri.UnescapeDataString(parts[1].Replace('+', ' ')) : string.Empty;
            if (!query.TryAdd(key, value))
            {
                return false;
            }
        }

        if (!query.TryGetValue("state", out string? state) || state != expectedState)
        {
            return false;
        }

        denied = query.ContainsKey("error");
        return !denied && query.TryGetValue("code", out code) && !string.IsNullOrWhiteSpace(code);
    }

    private static string Base64Url(byte[] bytes) => Convert.ToBase64String(bytes)
        .TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
