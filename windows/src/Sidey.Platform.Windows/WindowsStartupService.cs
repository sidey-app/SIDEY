using Microsoft.Win32;

namespace Sidey.Platform.Windows;

public sealed class WindowsStartupService
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "SIDEY";
    public const string BackgroundLaunchArgument = "--background";

    public bool IsEnabled()
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
        return key?.GetValue(ValueName) is string value
            && (StringComparer.OrdinalIgnoreCase.Equals(value, StartupCommand())
                || StringComparer.OrdinalIgnoreCase.Equals(value, QuotedExecutablePath()));
    }

    public void SetEnabled(bool enabled)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("Windows startup registration is required.");
        }

        using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true);
        if (enabled)
        {
            key.SetValue(ValueName, StartupCommand(), RegistryValueKind.String);
        }
        else
        {
            key.DeleteValue(ValueName, throwOnMissingValue: false);
        }
    }

    public void UpgradeEnabledRegistration()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true);
        if (key.GetValue(ValueName) is string value
            && StringComparer.OrdinalIgnoreCase.Equals(value, QuotedExecutablePath()))
        {
            key.SetValue(ValueName, StartupCommand(), RegistryValueKind.String);
        }
    }

    public static bool IsBackgroundLaunch(string? arguments) =>
        StringComparer.OrdinalIgnoreCase.Equals(
            arguments?.Trim(),
            BackgroundLaunchArgument);

    private static string StartupCommand() =>
        $"{QuotedExecutablePath()} {BackgroundLaunchArgument}";

    private static string QuotedExecutablePath() =>
        $"\"{SideyDeploymentPaths.LauncherPath()}\"";
}
