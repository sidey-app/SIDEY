using System.Reflection;
using Sidey.Infrastructure;

namespace Sidey.Platform.Windows.Tests;

public sealed class RuntimeConfigurationTests
{
    [Theory]
    [InlineData("https://example.supabase.co", true)]
    [InlineData("http://localhost:54321", true)]
    [InlineData("http://127.0.0.1:54321", true)]
    [InlineData("http://example.supabase.co", false)]
    public void BackendOverrideAllowsOnlyHttpsOrLoopbackHttp(string value, bool expected)
    {
        Assert.Equal(expected, SupabaseRuntimeConfiguration.IsAllowedBackend(new Uri(value)));
    }

    [Theory]
    [InlineData("sb_publishable_public", false)]
    [InlineData("sb_secret_do-not-ship", true)]
    [InlineData("service_role_do-not-ship", true)]
    [InlineData("eyJhbGciOiJub25lIn0.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature", true)]
    public void SecretAndServiceRoleKeysAreRejected(string value, bool expected)
    {
        Assert.Equal(expected, SupabaseRuntimeConfiguration.LooksLikeSecretKey(value));
    }

    [Fact]
    public void ProductionFallbackMatchesTheMacClientBackend()
    {
        Assert.Equal("whtejsviizgejauasqqt.supabase.co", SupabaseRuntimeConfiguration.ProductionHost);
        Assert.StartsWith("sb_publishable_", SupabaseRuntimeConfiguration.ProductionPublishableKey);
    }

    [Theory]
    [InlineData("https://staging.example.com", "1", true, true)]
    [InlineData("http://localhost:54321", "1", true, true)]
    [InlineData("https://whtejsviizgejauasqqt.supabase.co", "1", true, false)]
    [InlineData("https://staging.example.com", "true", true, false)]
    [InlineData("https://staging.example.com", "1", false, false)]
    [InlineData("http://staging.example.com", "1", true, false)]
    public void DevelopmentCommerceRequiresCompileRuntimeAndNonProductionGates(
        string backendUrl,
        string? optIn,
        bool compiledSupport,
        bool expected)
    {
        var configuration = new SupabaseRuntimeConfiguration(
            new Uri(backendUrl),
            "sb_publishable_test");

        Assert.Equal(
            expected,
            WindowsCommerceConfiguration.IsEnabled(configuration, optIn, compiledSupport));
    }

    [Fact]
    public void CommerceNetworkSurfaceMatchesTheCompileTimeGate()
    {
        MethodInfo? commerceStateMethod = typeof(SupabaseBackendGateway).GetMethod(
            "GetWindowsCommerceStateAsync");
        MethodInfo? identityLinkMethod = typeof(SupabaseAnonymousAuthService).GetMethod(
            "BeginGoogleIdentityLinkAsync");

#if SIDEY_DEVELOPMENT_COMMERCE
        Assert.NotNull(commerceStateMethod);
        Assert.NotNull(identityLinkMethod);
#else
        Assert.Null(commerceStateMethod);
        Assert.Null(identityLinkMethod);
#endif
    }
}
