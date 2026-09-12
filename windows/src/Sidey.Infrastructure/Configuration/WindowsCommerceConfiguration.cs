namespace Sidey.Infrastructure.Configuration;

public static class WindowsCommerceConfiguration
{
    public const string OptInEnvironmentVariable = "SIDEY_WINDOWS_DEVELOPMENT_COMMERCE";

    public static bool IsEnabled(SupabaseRuntimeConfiguration configuration)
    {
#if SIDEY_DEVELOPMENT_COMMERCE
        return IsEnabled(
            configuration,
            Environment.GetEnvironmentVariable(OptInEnvironmentVariable),
            compiledSupport: true);
#else
        _ = configuration;
        return false;
#endif
    }

    internal static bool IsEnabled(
        SupabaseRuntimeConfiguration configuration,
        string? optIn,
        bool compiledSupport)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        return compiledSupport
            && StringComparer.Ordinal.Equals(optIn, "1")
            && !StringComparer.OrdinalIgnoreCase.Equals(
                configuration.Url.Host,
                SupabaseRuntimeConfiguration.ProductionHost)
            && (configuration.Url.Scheme == Uri.UriSchemeHttps
                || (configuration.Url.Scheme == Uri.UriSchemeHttp
                    && configuration.Url.IsLoopback));
    }
}
