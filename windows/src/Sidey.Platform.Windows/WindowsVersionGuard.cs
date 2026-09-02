namespace Sidey.Platform.Windows;

public static class WindowsVersionGuard
{
    // Windows App SDK 1.8 supports Windows 10 version 1809 and later. Mica is
    // enabled separately on Windows 11, with a normal WinUI surface fallback.
    public const int MinimumBuild = 17763;
    public const string StartupSmokeEnvironmentVariable = "SIDEY_STARTUP_SMOKE";

    public static bool IsSupported() =>
        OperatingSystem.IsWindowsVersionAtLeast(10, 0, MinimumBuild);

    public static bool CanLaunchMainWindow() =>
        IsSupported()
        || IsCiStartupSmokeOverride(
            Environment.GetEnvironmentVariable("CI"),
            Environment.GetEnvironmentVariable(StartupSmokeEnvironmentVariable));

    public static bool IsCiStartupSmokeOverride(string? ci, string? startupSmoke) =>
        string.Equals(ci, "true", StringComparison.OrdinalIgnoreCase)
        && string.Equals(startupSmoke, "1", StringComparison.Ordinal);
}
