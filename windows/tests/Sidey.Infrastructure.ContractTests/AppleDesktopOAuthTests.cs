using System.Security.Cryptography;
using System.Text;
using Sidey.Core.Abstractions;
using Sidey.Infrastructure.Authentication;
using Sidey.Infrastructure.Configuration;

namespace Sidey.Infrastructure.ContractTests;

public sealed class AppleDesktopOAuthTests
{
    private static readonly SideyRuntimeConfiguration s_configuration = new(new Uri("https://api.sidey.app/api"),
        AppleServiceId: "app.sidey.windows", AppleRedirectUri: new Uri("https://sidey.app/auth/apple/windows"));

    [Fact]
    public void HybridRequestUsesFreshStateHashedServerNonceAndFragmentWithoutEmailScope()
    {
        const string Nonce = "server-issued-nonce";
        var first = new AppleDesktopOAuth(s_configuration, Nonce);
        var second = new AppleDesktopOAuth(s_configuration, Nonce);
        Dictionary<string, string> query = Query(first.AuthorizationUri.Query);
        Assert.Equal("https://appleid.apple.com/auth/authorize", first.AuthorizationUri.GetLeftPart(UriPartial.Path));
        Assert.Equal("fragment", query["response_mode"]);
        Assert.Equal("code id_token", query["response_type"]);
        Assert.Equal(Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(Nonce))), query["nonce"]);
        Assert.Equal(s_configuration.AppleRedirectUri!.AbsoluteUri, query["redirect_uri"]);
        Assert.False(query.ContainsKey("scope"));
        Assert.NotEqual(query["state"], Query(second.AuthorizationUri.Query)["state"]);
    }

    [Theory]
    [InlineData("https://sidey.app.attacker.test/auth/apple/windows")]
    [InlineData("http://sidey.app/auth/apple/windows")]
    [InlineData("https://sidey.app:444/auth/apple/windows")]
    [InlineData("https://sidey.app/auth/apple/other")]
    public void SimilarRedirectOriginsCannotReceiveProof(string url)
    {
        var request = new AppleDesktopOAuth(s_configuration, "nonce");
        Assert.False(request.IsCallback(new Uri(url)));
        Assert.Throws<AuthenticationRequiredException>(() => request.Complete(new Uri(url + "#state=wrong&id_token=proof&code=code")));
    }

    [Fact]
    public void ExactCallbackRequiresStateAndBothProofValuesWithoutDuplicates()
    {
        var request = new AppleDesktopOAuth(s_configuration, "nonce");
        string state = Query(request.AuthorizationUri.Query)["state"];
        string endpoint = request.RedirectUri.AbsoluteUri;
        Assert.Equal(new AppleIdentityProof("identity", "one-time-code"),
            request.Complete(new Uri(endpoint + $"#state={state}&id_token=identity&code=one-time-code")));
        Assert.Throws<AuthenticationRequiredException>(() => request.Complete(new Uri(endpoint + "#state=wrong&id_token=identity&code=code")));
        Assert.Throws<AuthenticationRequiredException>(() => request.Complete(new Uri(endpoint + $"#state={state}&state={state}&id_token=identity&code=code")));
        Assert.Throws<AuthenticationRequiredException>(() => request.Complete(new Uri(endpoint + $"#state={state}&code=code")));
        Assert.Throws<OperationCanceledException>(() => request.Complete(new Uri(endpoint + $"#state={state}&error=access_denied")));
    }

    [Fact]
    public void MissingProviderConfigurationFailsBeforeOpeningAnyWindow()
    {
        Assert.Throws<InvalidOperationException>(() => new AppleDesktopOAuth(s_configuration with { AppleServiceId = "" }, "nonce"));
        Assert.Throws<InvalidOperationException>(() => new AppleDesktopOAuth(s_configuration with { AppleRedirectUri = new Uri("http://localhost/callback") }, "nonce"));
    }

    private static Dictionary<string, string> Query(string query) => query.TrimStart('?').Split('&')
        .Select(part => part.Split('=', 2)).ToDictionary(part => Uri.UnescapeDataString(part[0]), part => Uri.UnescapeDataString(part[1]));
}
