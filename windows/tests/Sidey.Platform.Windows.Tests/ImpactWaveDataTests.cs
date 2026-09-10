using System.Buffers.Binary;

namespace Sidey.Platform.Windows.Tests;

public sealed class ImpactWaveDataTests
{
    private static byte[] Wave()
    {
        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream);
        writer.Write("RIFF"u8);
        writer.Write(50);
        writer.Write("WAVE"u8);
        writer.Write("JUNK"u8);
        writer.Write(1);
        writer.Write((byte)42);
        writer.Write((byte)0);
        writer.Write("fmt "u8);
        writer.Write(16);
        writer.Write((ushort)1);
        writer.Write((ushort)1);
        writer.Write(48000);
        writer.Write(96000);
        writer.Write((ushort)2);
        writer.Write((ushort)16);
        writer.Write("data"u8);
        writer.Write(4);
        writer.Write(new byte[] { 1, 2, 3, 4 });
        return stream.ToArray();
    }

    [Fact]
    public void ReadsPcmAfterPaddedMetadataChunk() => Assert.Equal(new byte[] { 1, 2, 3, 4 }, ImpactWaveData.Read(Wave()));

    [Fact]
    public void RejectsTruncatedContainerAndOversizedChunk()
    {
        byte[] file = Wave();
        Assert.Throws<InvalidDataException>(() => ImpactWaveData.Read(file.AsSpan(0, file.Length - 1)));
        BinaryPrimitives.WriteUInt32LittleEndian(file.AsSpan(16, 4), uint.MaxValue);
        Assert.Throws<InvalidDataException>(() => ImpactWaveData.Read(file));
    }

    [Theory]
    [InlineData(30)] // Compression tag.
    [InlineData(32)] // Channel count.
    [InlineData(34)] // Sample rate.
    [InlineData(38)] // Byte rate.
    [InlineData(42)] // Block alignment.
    [InlineData(44)] // Sample width.
    public void RejectsFormatsThatDoNotMatchPreparedOutput(int offset)
    {
        byte[] file = Wave();
        file[offset] ^= 0xff;
        Assert.Throws<InvalidDataException>(() => ImpactWaveData.Read(file));
    }
}
