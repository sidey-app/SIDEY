using Sidey.Core.Domain;
using System.Buffers.Binary;
using System.Security.Cryptography;

namespace Sidey.Core.Tests;

public sealed class CharacterCatalogTests
{
    [Fact]
    public void NativeVerticalSliceExposesOnlyHamsterContract()
    {
        var hamster = VerticalSliceCharacterCatalog.Hamster;

        Assert.Equal("pixel_hamster", hamster.Id);
        Assert.Equal(24, hamster.FrameWidth);
        Assert.Equal(24, hamster.FrameHeight);
        Assert.Equal(10, hamster.FrameCount);
        Assert.Equal(3, hamster.FootBaselinePixel);
        Assert.Equal(0..2, hamster.Frames.Idle);
        Assert.Equal(2..6, hamster.Frames.Walk);
        Assert.Equal(6..8, hamster.Frames.Doze);
        Assert.Equal(8..10, hamster.Frames.Offline);
        Assert.Equal("pixel_hamster", VerticalSliceCharacterCatalog.NormalizeId("minty_pup"));
        Assert.Equal("pixel_hamster", VerticalSliceCharacterCatalog.NormalizeId("pixel_cat"));
    }

    [Fact]
    public void HamsterAssetMatchesMacSheetContractAndHash()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "TestAssets", "pixel_hamster.png");
        var bytes = File.ReadAllBytes(path);

        Assert.True(bytes.AsSpan(0, 8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }));
        Assert.Equal("IHDR", System.Text.Encoding.ASCII.GetString(bytes, 12, 4));
        Assert.Equal(240, BinaryPrimitives.ReadInt32BigEndian(bytes.AsSpan(16, 4)));
        Assert.Equal(24, BinaryPrimitives.ReadInt32BigEndian(bytes.AsSpan(20, 4)));
        Assert.Equal(8, bytes[24]);
        Assert.Equal(6, bytes[25]);
        Assert.Equal(
            "43171c1dd614629058b6d593c57ca0e5841b0be03a04a05181dfda67c53a7f45",
            Convert.ToHexStringLower(SHA256.HashData(bytes)));
    }

    [Fact]
    public void HamsterRuntimeBgraIsDeterministicAndMatchesSheetDimensions()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "TestAssets", "pixel_hamster.bgra");
        var bytes = File.ReadAllBytes(path);

        Assert.Equal(240 * 24 * 4, bytes.Length);
        Assert.Equal(
            "8532df2c91beb19d9794e16576df5b9e37397ed764869c0f734c4abefcc2b088",
            Convert.ToHexStringLower(SHA256.HashData(bytes)));
    }
}
