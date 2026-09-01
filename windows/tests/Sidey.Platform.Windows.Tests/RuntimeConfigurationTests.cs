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
}
