using Sidey.Overlay;

namespace Sidey.Platform.Windows.Tests;

public sealed class CharacterAssetPathResolverTests
{
    [Fact]
    public void SingleFilePublishUsesAssetsBesideTheExecutable()
    {
        string root = CreateTemporaryDirectory();
        try
        {
            string executableDirectory = Path.Combine(root, "install");
            string executableAssetRoot = Path.Combine(executableDirectory, "Assets", "Characters");
            string extractionDirectory = Path.Combine(root, "extraction");
            Directory.CreateDirectory(executableAssetRoot);
            Directory.CreateDirectory(extractionDirectory);

            string resolved = CharacterAssetPathResolver.Resolve(
                Path.Combine(executableDirectory, "SIDEY.exe"),
                extractionDirectory);

            Assert.Equal(executableAssetRoot, resolved);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void DevelopmentBuildFallsBackToAppBaseAssets()
    {
        string root = CreateTemporaryDirectory();
        try
        {
            string executableDirectory = Path.Combine(root, "host");
            string appBaseDirectory = Path.Combine(root, "app");
            string appBaseAssetRoot = Path.Combine(appBaseDirectory, "Assets", "Characters");
            Directory.CreateDirectory(executableDirectory);
            Directory.CreateDirectory(appBaseAssetRoot);

            string resolved = CharacterAssetPathResolver.Resolve(
                Path.Combine(executableDirectory, "testhost.exe"),
                appBaseDirectory);

            Assert.Equal(appBaseAssetRoot, resolved);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void StructuredPublishUsesAssetsAboveTheRuntimeDirectory()
    {
        string root = CreateTemporaryDirectory();
        try
        {
            string deploymentRoot = Path.Combine(root, "live");
            string runtimeDirectory = Path.Combine(deploymentRoot, "Runtime");
            string assetRoot = Path.Combine(deploymentRoot, "Assets", "Characters");
            Directory.CreateDirectory(runtimeDirectory);
            Directory.CreateDirectory(assetRoot);

            string resolved = CharacterAssetPathResolver.Resolve(
                Path.Combine(runtimeDirectory, "SIDEY.Host.exe"),
                runtimeDirectory);

            Assert.Equal(assetRoot, resolved);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private static string CreateTemporaryDirectory()
    {
        string path = Path.Combine(Path.GetTempPath(), $"sidey-assets-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }
}
