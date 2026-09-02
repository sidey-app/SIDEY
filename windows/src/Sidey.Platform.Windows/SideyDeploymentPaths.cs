namespace Sidey.Platform.Windows;

public static class SideyDeploymentPaths
{
    public const string RuntimeDirectoryName = "Runtime";
    public const string HostExecutableName = "SIDEY.Host.exe";
    public const string LauncherExecutableName = "SIDEY.exe";

    public static string DeploymentRoot(
        string? processPath = null,
        string? appBaseDirectory = null)
    {
        processPath ??= Environment.ProcessPath;
        appBaseDirectory ??= AppContext.BaseDirectory;

        string? processDirectory = string.IsNullOrWhiteSpace(processPath)
            ? null
            : Path.GetDirectoryName(Path.GetFullPath(processPath));
        string? root = ParentOfRuntimeDirectory(processDirectory);
        if (root is not null)
        {
            return root;
        }

        string fullAppBase = Path.GetFullPath(appBaseDirectory);
        root = ParentOfRuntimeDirectory(fullAppBase);
        return root ?? processDirectory ?? fullAppBase;
    }

    public static string LauncherPath(
        string? processPath = null,
        string? appBaseDirectory = null) =>
        Path.Combine(
            DeploymentRoot(processPath, appBaseDirectory),
            LauncherExecutableName);

    private static string? ParentOfRuntimeDirectory(string? directory)
    {
        if (string.IsNullOrWhiteSpace(directory)
            || !string.Equals(
                Path.GetFileName(directory.TrimEnd(
                    Path.DirectorySeparatorChar,
                    Path.AltDirectorySeparatorChar)),
                RuntimeDirectoryName,
                StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }
        return Directory.GetParent(directory)?.FullName;
    }
}
