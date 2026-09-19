namespace Sidey.Infrastructure.Configuration;

public static class WindowsCommerceConfiguration
{
    public const string OptInEnvironmentVariable = "SIDEY_WINDOWS_DEVELOPMENT_COMMERCE";
    public const string StagingHost = "fjglrvhvdthntkvrduyi.supabase.co";

    public static bool IsEnabled(SupabaseRuntimeConfiguration configuration) =>
        IsEnabled(configuration, Environment.GetEnvironmentVariable(OptInEnvironmentVariable),
#if SIDEY_DEVELOPMENT_COMMERCE
            compiledSupport: true);
#else
            compiledSupport: false);
#endif

    public static bool IsProduction(SupabaseRuntimeConfiguration configuration) =>
        IsExactOrigin(configuration.Url, SupabaseRuntimeConfiguration.ProductionHost);

    internal static bool IsEnabled(
        SupabaseRuntimeConfiguration configuration,
        string? optIn,
        bool compiledSupport)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        return IsProduction(configuration)
            || (compiledSupport && StringComparer.Ordinal.Equals(optIn, "1")
                && (IsExactOrigin(configuration.Url, StagingHost)
                    || (configuration.Url.Scheme == Uri.UriSchemeHttp
                        && configuration.Url.IsLoopback
                        && string.IsNullOrEmpty(configuration.Url.UserInfo)
                        && configuration.Url.AbsolutePath == "/"
                        && string.IsNullOrEmpty(configuration.Url.Query)
                        && string.IsNullOrEmpty(configuration.Url.Fragment))));
    }

    private static bool IsExactOrigin(Uri uri, string host) =>
        uri.Scheme == Uri.UriSchemeHttps && uri.IsDefaultPort
        && StringComparer.OrdinalIgnoreCase.Equals(uri.Host, host)
        && string.IsNullOrEmpty(uri.UserInfo) && uri.AbsolutePath == "/"
        && string.IsNullOrEmpty(uri.Query) && string.IsNullOrEmpty(uri.Fragment);
}
