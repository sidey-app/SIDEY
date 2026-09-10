namespace Sidey.Overlay;

internal static class CharacterAssetPathResolver
{
    public static string Resolve(
        string? processPath = null,
        string? appBaseDirectory = null)
    {
        processPath ??= Environment.ProcessPath;
        appBaseDirectory ??= AppContext.BaseDirectory;

        string deploymentRoot = Sidey.Platform.Windows.SideyDeploymentPaths.DeploymentRoot(
            processPath,
            appBaseDirectory);
        string executableAssetRoot = Path.Combine(
            deploymentRoot,
            "Assets",
            "Characters");
        if (Directory.Exists(executableAssetRoot))
        {
            return executableAssetRoot;
        }

        string appBaseAssetRoot = Path.Combine(appBaseDirectory, "Assets", "Characters");
        return Directory.Exists(appBaseAssetRoot)
            ? appBaseAssetRoot
            : executableAssetRoot;
    }
}
