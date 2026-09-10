using System.Xml.Linq;

namespace Sidey.Platform.Windows.Tests;

public sealed class ApplicationIconAssetTests
{
    private static readonly int[] s_expectedSizes = [16, 20, 24, 32, 40, 48, 64, 128, 256];

    [Fact]
    public void AppProjectPackagesTheMultiSizePngIcon()
    {
        var project = XDocument.Load(RepositoryPath(
            "windows",
            "src",
            "Sidey.App",
            "Sidey.App.csproj"));
        string? configuredIcon = project.Descendants("ApplicationIcon").Single().Value;

        Assert.Equal("Assets\\Icons\\SideyAppIcon.ico", configuredIcon);

        byte[] icon = File.ReadAllBytes(RepositoryPath(
            "windows",
            "src",
            "Sidey.App",
            "Assets",
            "Icons",
            "SideyAppIcon.ico"));
        Assert.Equal(0, BitConverter.ToUInt16(icon, 0));
        Assert.Equal(1, BitConverter.ToUInt16(icon, 2));

        ushort imageCount = BitConverter.ToUInt16(icon, 4);
        Assert.Equal(s_expectedSizes.Length, imageCount);
        int[] embeddedSizes = new int[imageCount];
        for (int index = 0; index < imageCount; index++)
        {
            int entryOffset = 6 + (index * 16);
            embeddedSizes[index] = icon[entryOffset] == 0 ? 256 : icon[entryOffset];
            uint imageLength = BitConverter.ToUInt32(icon, entryOffset + 8);
            uint imageOffset = BitConverter.ToUInt32(icon, entryOffset + 12);
            Assert.True(imageLength > 8);
            Assert.True(imageOffset + imageLength <= icon.Length);
            int imageStart = checked((int)imageOffset);
            Assert.Equal(
                new byte[] { 0x89, (byte)'P', (byte)'N', (byte)'G' },
                icon[imageStart..(imageStart + 4)]);
        }

        Assert.Equal(s_expectedSizes, embeddedSizes);
        Assert.All(
            s_expectedSizes,
            size => Assert.True(File.Exists(RepositoryPath(
                "windows",
                "src",
                "Sidey.App",
                "Assets",
                "Icons",
                $"SideyAppIcon-{size}.png"))));
    }

    private static string RepositoryPath(params string[] pathSegments)
    {
        DirectoryInfo? root = new(AppContext.BaseDirectory);
        while (root is not null && !Directory.Exists(Path.Combine(root.FullName, "windows", "src")))
        {
            root = root.Parent;
        }

        Assert.NotNull(root);
        return Path.Combine([root!.FullName, .. pathSegments]);
    }
}
