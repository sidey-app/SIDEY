namespace Sidey.Platform.Windows;

public static class WindowsVersionGuard
{
    public const int MinimumBuild = 26200;

    public static bool IsSupported() =>
        OperatingSystem.IsWindowsVersionAtLeast(10, 0, MinimumBuild);
}
