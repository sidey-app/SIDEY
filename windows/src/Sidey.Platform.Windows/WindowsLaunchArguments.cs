namespace Sidey.Platform.Windows;

public static class WindowsLaunchArguments
{
    public static string? Resolve(
        string? activationArguments,
        IReadOnlyList<string> processArguments)
    {
        ArgumentNullException.ThrowIfNull(processArguments);
        if (!string.IsNullOrWhiteSpace(activationArguments))
        {
            return activationArguments;
        }

        return processArguments.Count > 1
            ? string.Join(' ', processArguments.Skip(1))
            : null;
    }
}
