using Sidey.Core.Abstractions;
using Sidey.Infrastructure.Authentication;
using Sidey.Infrastructure.Configuration;

namespace Sidey.Platform.Windows.Tests;

public sealed class RuntimeConfigurationTests
{
    [Theory]
    [InlineData("https://staging.sidey.app/api", true)]
    [InlineData("http://localhost:8080/api", true)]
    [InlineData("http://127.0.0.1:8080/api", true)]
    [InlineData("http://staging.sidey.app/api", false)]
    [InlineData("https://user:password@staging.sidey.app/api", false)]
    [InlineData("https://staging.sidey.app/api?other=1", false)]
    [InlineData("https://staging.sidey.app/api#other", false)]
    public void BackendOverrideAllowsOnlySafeHttpsOrLoopbackHttp(string value, bool expected)
    {
        Assert.Equal(expected, SideyRuntimeConfiguration.IsAllowedBackend(new Uri(value)));
    }

    [Theory]
    [InlineData("sb_publishable_public", false)]
    [InlineData("sb_secret_do-not-ship", true)]
    [InlineData("service_role_do-not-ship", true)]
    [InlineData("eyJhbGciOiJub25lIn0.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature", true)]
    public void LegacyVerifierCannotEmbedSecretOrServiceRoleKeys(string value, bool expected)
    {
        Assert.Equal(expected, SideyRuntimeConfiguration.LooksLikeSecretKey(value));
    }

    [Fact]
    public void DefaultUsesSpringApiAndLegacyProofHasDistinctConfiguration()
    {
        var configuration = SideyRuntimeConfiguration.FromEnvironment(new Dictionary<string, string?>());
        Assert.Equal("https://api.sidey.app/api", configuration.ApiBaseUrl.AbsoluteUri);
        Assert.Equal("whtejsviizgejauasqqt.supabase.co", configuration.LegacyUrl.Host);
        Assert.Empty(configuration.GoogleClientId);
    }

    [Fact]
    public void ApiConfigurationDoesNotRequireSupabaseKeys()
    {
        var configuration = SideyRuntimeConfiguration.FromEnvironment(new Dictionary<string, string?>
        {
            ["SIDEY_API_BASE_URL"] = "http://127.0.0.1:8080/api",
            ["SIDEY_GOOGLE_CLIENT_ID"] = "public-installed-client",
        });
        Assert.Equal("public-installed-client", configuration.GoogleClientId);
        Assert.Equal("/api", configuration.ApiBaseUrl.AbsolutePath);
    }

    [Fact]
    public void CredentialTargetsPreserveLegacyAndIsolateNewBackendSessions()
    {
        var first = new SideyRuntimeConfiguration(new Uri("https://staging.sidey.app/api"));
        var second = new SideyRuntimeConfiguration(new Uri("https://api.sidey.app/api"));
        Assert.Equal("SIDEY/SupabaseSession", WindowsCredentialStore.CredentialTarget(CredentialKey.SupabaseSession, first.BackendFingerprint));
        Assert.NotEqual(WindowsCredentialStore.CredentialTarget(CredentialKey.SideySession, first.BackendFingerprint),
            WindowsCredentialStore.CredentialTarget(CredentialKey.SideySession, second.BackendFingerprint));
        Assert.NotEqual(WindowsCredentialStore.CredentialTarget(CredentialKey.SideySession, first.BackendFingerprint),
            WindowsCredentialStore.CredentialTarget(CredentialKey.SupabaseSession, first.BackendFingerprint));
    }

    [Theory]
    [InlineData("https://staging.example.com/api", true)]
    [InlineData("http://localhost:8080/api", true)]
    [InlineData("https://api.sidey.app/api", true)]
    [InlineData("http://staging.example.com/api", false)]
    public void CommerceUsesTheAuthenticatedServiceInEveryBuild(string backendUrl, bool expected)
    {
        var configuration = new SideyRuntimeConfiguration(new Uri(backendUrl));
        Assert.Equal(expected, WindowsCommerceConfiguration.IsEnabled(configuration));
    }
}
