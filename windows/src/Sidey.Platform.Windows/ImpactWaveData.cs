using System.Buffers.Binary;

namespace Sidey.Platform.Windows;

/// <summary>The approved impacts use uncompressed 48 kHz, mono, 16-bit PCM.</summary>
public static class ImpactWaveData
{
    public static byte[] Read(ReadOnlySpan<byte> file)
    {
        if (file.Length < 12 || !file[..4].SequenceEqual("RIFF"u8) || !file.Slice(8, 4).SequenceEqual("WAVE"u8)
            || BinaryPrimitives.ReadUInt32LittleEndian(file.Slice(4, 4)) != file.Length - 8)
            throw new InvalidDataException("Invalid impact WAV container.");
        bool validFormat = false;
        ReadOnlySpan<byte> data = default;
        for (int offset = 12; offset < file.Length;)
        {
            if (file.Length - offset < 8)
                throw new InvalidDataException("Truncated WAV chunk.");
            uint length = BinaryPrimitives.ReadUInt32LittleEndian(file.Slice(offset + 4, 4));
            if (length > file.Length - offset - 8)
                throw new InvalidDataException("Truncated WAV data.");
            var chunk = file.Slice(offset + 8, (int)length);
            if (file.Slice(offset, 4).SequenceEqual("fmt "u8))
            {
                validFormat = chunk.Length >= 16
                    && BinaryPrimitives.ReadUInt16LittleEndian(chunk) == 1
                    && BinaryPrimitives.ReadUInt16LittleEndian(chunk[2..]) == 1
                    && BinaryPrimitives.ReadUInt32LittleEndian(chunk[4..]) == 48000
                    && BinaryPrimitives.ReadUInt32LittleEndian(chunk[8..]) == 96000
                    && BinaryPrimitives.ReadUInt16LittleEndian(chunk[12..]) == 2
                    && BinaryPrimitives.ReadUInt16LittleEndian(chunk[14..]) == 16;
            }
            else if (file.Slice(offset, 4).SequenceEqual("data"u8))
                data = chunk;
            offset += 8 + (int)length + ((int)length & 1);
        }
        if (!validFormat || data.IsEmpty || data.Length % 2 != 0)
            throw new InvalidDataException("Impact WAV must contain 48 kHz mono 16-bit PCM.");
        return data.ToArray();
    }
}
