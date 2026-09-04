using System.Buffers.Binary;
using System.Security.Cryptography;
using Sidey.Core.Domain;
using Sidey.Overlay;

namespace Sidey.Platform.Windows.Tests;

public sealed class CharacterThrowAssetTests
{
    private static readonly IReadOnlyDictionary<string, string> PngHashes =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["Characters/pixel_hamster/throw_hit"] = "b9915afdbb5476b17ea7b7f0a06eea09cc20b96dd1995328bdae2f806c3285c8",
            ["Characters/pixel_cat/throw_hit"] = "128e020aab718d8d45e81f599c221467b46f27aa809c45b1d873580cdaffcc62",
            ["Characters/pixel_puppy/throw_hit"] = "38d2858c97b456be17f34fd6b93df862e9c0d3b72e5592bb0e625e64110c5744",
            ["Characters/pixel_rabbit/throw_hit"] = "f641ebbba64e8c23d33173ff04d4907d3e15955024dd72e3f6e7d9b3e20fec84",
            ["Characters/pixel_penguin/throw_hit"] = "7ee5ea2b90994400a1b4dd252ed2affb095416597422a8ef4cb0ae54b3fb7f77",
            ["Characters/pixel_guinea_pig/throw_hit"] = "384157773baa55bd4a5f8586d179ab7eb43f42fb4204c306490784551e38ae1d",
            ["Characters/pixel_monkey/throw_hit"] = "059a288dde75695febec8a42303dc63f126636b094e3896b795b6a4ac1cce39a",
            ["Characters/pixel_chinchilla/throw_hit"] = "a6dd2b4f1837812bc9fd0d979fe379c4362ed8018b9d5e6991e5c28d53265b02",
            ["Characters/pixel_starlight_upalupa/throw_hit"] = "7a9bae8b1359f432857e026c972e3bc99777539ce7cfff89bc01e95d1938de75",
            ["Throwables/patch_soft_ball/sprite"] = "cdde7f417c5d8d82d0f4df6b03fa8e7d494d98a37d75aa66699505d7c87c53fe",
            ["Throwables/mini_paprika/sprite"] = "85b8d0525a865e531882a736561e9b7c4fbb6a2c3f80d91b456c4c4a7425724d",
            ["Throwables/banana/sprite"] = "9cfca454ff6305fdd374c08f64c3c21e3af278166ffe15f7f81a183bb214f138",
            ["Throwables/dust_bath_pouch/sprite"] = "b68022f5fe1a1a6a57fe56a01f73bae3d14b27d76f2dcbf10c6686b979634a65",
            ["Throwables/starlight_orb/sprite"] = "08cf8ec8dc680ae07dcd83de9d56948873445470c6b15b5ad22e770f4277984c",
        };

    [Fact]
    public void ApprovedPngsAndPreconvertedBgraSheetsMatchTheContract()
    {
        foreach (var pair in PngHashes)
        {
            var png = File.ReadAllBytes(AssetPath(pair.Key + ".png"));
            Assert.Equal(pair.Value, Convert.ToHexStringLower(SHA256.HashData(png)));
            Assert.Equal("IHDR", System.Text.Encoding.ASCII.GetString(png, 12, 4));
            var width = BinaryPrimitives.ReadInt32BigEndian(png.AsSpan(16, 4));
            var height = BinaryPrimitives.ReadInt32BigEndian(png.AsSpan(20, 4));
            Assert.Equal(192, width);
            Assert.Equal(pair.Key.StartsWith("Characters/", StringComparison.Ordinal) ? 24 : 16, height);
            Assert.Equal(width * height * 4, File.ReadAllBytes(AssetPath(pair.Key + ".bgra")).Length);
        }
    }

    [Fact]
    public void PaidCharacterThrowsKeepTheirOwnActionsAndUniqueObjects()
    {
        using var cache = new CharacterThrowFrameCache(
            Path.Combine(AppContext.BaseDirectory, "Assets", "Characters"),
            Path.Combine(AppContext.BaseDirectory, "Assets", "Throwables"),
            scale: 1,
            edge: OverlayEdge.Bottom);

        var hamsterAction = cache.ActionFrame("pixel_hamster", frame: 0, flipped: false).ToArray();
        Assert.False(hamsterAction.SequenceEqual(cache.ActionFrame("pixel_guinea_pig", frame: 0, flipped: false).ToArray()));
        Assert.False(hamsterAction.SequenceEqual(cache.ActionFrame("pixel_monkey", frame: 0, flipped: false).ToArray()));
        Assert.False(hamsterAction.SequenceEqual(cache.ActionFrame("pixel_chinchilla", frame: 0, flipped: false).ToArray()));
        Assert.False(hamsterAction.SequenceEqual(cache.ActionFrame("pixel_starlight_upalupa", frame: 0, flipped: false).ToArray()));
        Assert.Equal(hamsterAction, cache.ActionFrame("unknown_character", frame: 0, flipped: false).ToArray());

        var patchBall = cache.ObjectFrame("pixel_hamster", frame: 0).ToArray();
        Assert.False(patchBall.SequenceEqual(cache.ObjectFrame("pixel_guinea_pig", frame: 0).ToArray()));
        Assert.False(patchBall.SequenceEqual(cache.ObjectFrame("pixel_monkey", frame: 0).ToArray()));
        Assert.False(patchBall.SequenceEqual(cache.ObjectFrame("pixel_chinchilla", frame: 0).ToArray()));
        Assert.False(patchBall.SequenceEqual(cache.ObjectFrame("pixel_starlight_upalupa", frame: 0).ToArray()));
        Assert.Equal(patchBall, cache.ObjectFrame("unknown_character", frame: 0).ToArray());
    }

    private static string AssetPath(string relative) => Path.Combine(
        AppContext.BaseDirectory,
        "Assets",
        relative.Replace('/', Path.DirectorySeparatorChar));
}
