using Microsoft.Win32;

namespace Sidey.Platform.Windows.Startup;

public static class WindowsProtocolRegistration
{
    public static void EnsureCurrentUserDevelopmentCallback(string executablePath)
    {
        if (string.IsNullOrWhiteSpace(executablePath)
            || !Path.IsPathFullyQualified(executablePath))
        {
            throw new ArgumentException("A fully qualified executable path is required.", nameof(executablePath));
        }

        const string Scheme = WindowsAuthCallback.DevelopmentScheme;
        using RegistryKey key = Registry.CurrentUser.CreateSubKey($"Software\\Classes\\{Scheme}");
        key.SetValue(string.Empty, "URL:SIDEY development authentication callback");
        key.SetValue("URL Protocol", string.Empty);
        using RegistryKey command = key.CreateSubKey("shell\\open\\command");
        command.SetValue(string.Empty, $"\"{executablePath}\" \"%1\"");
    }
}
