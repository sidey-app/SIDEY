using Sidey.Overlay;

namespace Sidey.Platform.Windows.Tests;

public sealed class CharacterAssetPathResolverTests
{
    [Fact]
    public void SingleFilePublishUsesAssetsBesideTheExecutable()
    {
        var root = CreateTemporaryDirectory();
        try
        {
            var executableDirectory = Path.Combine(root, "install");
            var executableAssetRoot = Path.Combine(executableDirectory, "Assets", "Characters");
            var extractionDirectory = Path.Combine(root, "extraction");
            Directory.CreateDirectory(executableAssetRoot);
            Directory.CreateDirectory(extractionDirectory);

            var resolved = CharacterAssetPathResolver.Resolve(
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
        var root = CreateTemporaryDirectory();
        try
        {
            var executableDirectory = Path.Combine(root, "host");
            var appBaseDirectory = Path.Combine(root, "app");
            var appBaseAssetRoot = Path.Combine(appBaseDirectory, "Assets", "Characters");
            Directory.CreateDirectory(executableDirectory);
            Directory.CreateDirectory(appBaseAssetRoot);

            var resolved = CharacterAssetPathResolver.Resolve(
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
        var root = CreateTemporaryDirectory();
        try
        {
            var deploymentRoot = Path.Combine(root, "live");
            var runtimeDirectory = Path.Combine(deploymentRoot, "Runtime");
            var assetRoot = Path.Combine(deploymentRoot, "Assets", "Characters");
            Directory.CreateDirectory(runtimeDirectory);
            Directory.CreateDirectory(assetRoot);

            var resolved = CharacterAssetPathResolver.Resolve(
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
        var path = Path.Combine(Path.GetTempPath(), $"sidey-assets-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }
}
