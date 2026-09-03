namespace Sidey.Overlay;

internal static class CharacterAssetPathResolver
{
    public static string Resolve(
        string? processPath = null,
        string? appBaseDirectory = null)
    {
        processPath ??= Environment.ProcessPath;
        appBaseDirectory ??= AppContext.BaseDirectory;

        var deploymentRoot = Sidey.Platform.Windows.SideyDeploymentPaths.DeploymentRoot(
            processPath,
            appBaseDirectory);
        var executableAssetRoot = Path.Combine(
            deploymentRoot,
            "Assets",
            "Character");
        if (Directory.Exists(executableAssetRoot))
        {
            return executableAssetRoot;
        }

        var appBaseAssetRoot = Path.Combine(appBaseDirectory, "Assets", "Character");
        return Directory.Exists(appBaseAssetRoot)
            ? appBaseAssetRoot
            : executableAssetRoot;
    }
}
