namespace Sidey.Infrastructure.Configuration;

public static class WindowsCommerceConfiguration
{
    public static bool IsEnabled(SideyRuntimeConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        return SideyRuntimeConfiguration.IsAllowedBackend(configuration.ApiBaseUrl);
    }
}
