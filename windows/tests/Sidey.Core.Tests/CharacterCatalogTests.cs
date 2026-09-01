using Sidey.Core.Domain;
using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text.Json;

namespace Sidey.Core.Tests;

public sealed class CharacterCatalogTests
{
    [Fact]
    public void ProductCatalogContainsExactlyTheFiveConfirmedCharacters()
    {
        Assert.Equal(
            ["pixel_hamster", "pixel_cat", "pixel_puppy", "pixel_rabbit", "pixel_penguin"],
            PixelCharacterCatalog.All.Select(character => character.Id));

        Assert.All(PixelCharacterCatalog.All, character =>
        {
            Assert.Equal(24, character.FrameWidth);
            Assert.Equal(24, character.FrameHeight);
            Assert.Equal(10, character.FrameCount);
            Assert.Equal(3, character.FootBaselinePixel);
            Assert.Equal(0..2, character.Frames.Idle);
            Assert.Equal(2..6, character.Frames.Walk);
            Assert.Equal(6..8, character.Frames.Doze);
            Assert.Equal(8..10, character.Frames.Offline);
        });
    }

    [Theory]
    [InlineData("pixel_cat", "pixel_cat")]
    [InlineData("minty_pup", "pixel_hamster")]
    [InlineData("not_a_character", "pixel_hamster")]
    [InlineData(null, "pixel_hamster")]
    public void AliasAndUnknownIdsNormalizeWithoutSpeciesBranches(string? value, string expected)
    {
        Assert.Equal(expected, PixelCharacterCatalog.NormalizeId(value));
        Assert.Equal(expected, PixelCharacterCatalog.Get(value).Id);
    }

    [Fact]
    public void EveryAssetAndManifestMatchesTheCatalogContract()
    {
        foreach (var character in PixelCharacterCatalog.All)
        {
            var pngPath = AssetPath($"{character.Id}.png");
            var png = File.ReadAllBytes(pngPath);
            Assert.True(png.AsSpan(0, 8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }));
            Assert.Equal("IHDR", System.Text.Encoding.ASCII.GetString(png, 12, 4));
            Assert.Equal(240, BinaryPrimitives.ReadInt32BigEndian(png.AsSpan(16, 4)));
            Assert.Equal(24, BinaryPrimitives.ReadInt32BigEndian(png.AsSpan(20, 4)));
            Assert.Equal(8, png[24]);
            Assert.Equal(6, png[25]);
            Assert.Equal(character.SpriteSheetSha256, Convert.ToHexStringLower(SHA256.HashData(png)));

            var raw = File.ReadAllBytes(AssetPath($"{character.Id}.bgra"));
            Assert.Equal(240 * 24 * 4, raw.Length);

            using var manifest = JsonDocument.Parse(File.ReadAllBytes(
                AssetPath($"{character.Id}_manifest.json")));
            var root = manifest.RootElement;
            Assert.Equal(character.Id, root.GetProperty("character_id").GetString());
            Assert.Equal(character.DisplayName, root.GetProperty("display_name").GetString());
            Assert.Equal([24, 24], root.GetProperty("frame_pixel_size").EnumerateArray().Select(value => value.GetInt32()));
            Assert.Equal([240, 24], root.GetProperty("sheet_pixel_size").EnumerateArray().Select(value => value.GetInt32()));
            Assert.Equal(3, root.GetProperty("foot_baseline_pixel").GetInt32());
            Assert.Equal(character.SpriteSheetSha256, root.GetProperty("sha256").GetString());
            Assert.Equal(
                character.CompatibleAliases,
                root.GetProperty("legacy_aliases").EnumerateArray().Select(value => value.GetString()!).ToArray());
            var animations = root.GetProperty("animations");
            Assert.Equal([0, 1], Animation(animations, "idle"));
            Assert.Equal([2, 3, 4, 5], Animation(animations, "walk"));
            Assert.Equal([6, 7], Animation(animations, "doze"));
            Assert.Equal([8, 9], Animation(animations, "offline"));
            Assert.Equal(23040, root.GetProperty("runtime_bgra").GetProperty("byte_length").GetInt32());
            Assert.Equal("straight", root.GetProperty("runtime_bgra").GetProperty("alpha").GetString());
            Assert.Equal(
                Convert.ToHexStringLower(SHA256.HashData(raw)),
                root.GetProperty("runtime_bgra").GetProperty("sha256").GetString());
        }
    }

    [Fact]
    public void RendererAndFrameCacheDoNotContainSpeciesSpecificBranches()
    {
        var implementation = File.ReadAllText(AssetPath("LayeredPixelWorldRenderer.cs"))
            + File.ReadAllText(AssetPath("PixelCharacterFrameCache.cs"));

        foreach (var character in PixelCharacterCatalog.All)
        {
            Assert.False(implementation.Contains(character.Id, StringComparison.Ordinal));
        }
        Assert.False(implementation.Contains("minty_pup", StringComparison.Ordinal));
    }

    private static string AssetPath(string name) =>
        Path.Combine(AppContext.BaseDirectory, "TestAssets", name);

    private static int[] Animation(JsonElement animations, string name) =>
        animations.GetProperty(name).EnumerateArray().Select(value => value.GetInt32()).ToArray();
}
