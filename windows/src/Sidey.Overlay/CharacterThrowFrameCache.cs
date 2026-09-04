using System.Security.Cryptography;
using Sidey.Core.Domain;

namespace Sidey.Overlay;

internal sealed class CharacterThrowFrameCache : IDisposable
{
    internal const int ActionFrameCount = 8;
    internal const int ObjectFrameCount = 12;

    private static readonly IReadOnlyDictionary<string, string> ActionHashes =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["pixel_hamster"] = "b9915afdbb5476b17ea7b7f0a06eea09cc20b96dd1995328bdae2f806c3285c8",
            ["pixel_cat"] = "128e020aab718d8d45e81f599c221467b46f27aa809c45b1d873580cdaffcc62",
            ["pixel_puppy"] = "38d2858c97b456be17f34fd6b93df862e9c0d3b72e5592bb0e625e64110c5744",
            ["pixel_rabbit"] = "f641ebbba64e8c23d33173ff04d4907d3e15955024dd72e3f6e7d9b3e20fec84",
            ["pixel_penguin"] = "7ee5ea2b90994400a1b4dd252ed2affb095416597422a8ef4cb0ae54b3fb7f77",
            ["pixel_guinea_pig"] = "384157773baa55bd4a5f8586d179ab7eb43f42fb4204c306490784551e38ae1d",
            ["pixel_monkey"] = "059a288dde75695febec8a42303dc63f126636b094e3896b795b6a4ac1cce39a",
            ["pixel_chinchilla"] = "a6dd2b4f1837812bc9fd0d979fe379c4362ed8018b9d5e6991e5c28d53265b02",
            ["pixel_starlight_upalupa"] = "7a9bae8b1359f432857e026c972e3bc99777539ce7cfff89bc01e95d1938de75",
        };

    private static readonly IReadOnlyDictionary<string, string> ObjectHashes =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["patch_soft_ball"] = "cdde7f417c5d8d82d0f4df6b03fa8e7d494d98a37d75aa66699505d7c87c53fe",
            ["mini_paprika"] = "85b8d0525a865e531882a736561e9b7c4fbb6a2c3f80d91b456c4c4a7425724d",
            ["banana"] = "9cfca454ff6305fdd374c08f64c3c21e3af278166ffe15f7f81a183bb214f138",
            ["dust_bath_pouch"] = "b68022f5fe1a1a6a57fe56a01f73bae3d14b27d76f2dcbf10c6686b979634a65",
            ["starlight_orb"] = "08cf8ec8dc680ae07dcd83de9d56948873445470c6b15b5ad22e770f4277984c",
        };

    private static readonly IReadOnlyDictionary<string, string> CharacterObjects =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["pixel_hamster"] = "patch_soft_ball",
            ["pixel_cat"] = "patch_soft_ball",
            ["pixel_puppy"] = "patch_soft_ball",
            ["pixel_rabbit"] = "patch_soft_ball",
            ["pixel_penguin"] = "patch_soft_ball",
            ["pixel_guinea_pig"] = "mini_paprika",
            ["pixel_monkey"] = "banana",
            ["pixel_chinchilla"] = "dust_bath_pouch",
            ["pixel_starlight_upalupa"] = "starlight_orb",
        };

    private static readonly IReadOnlyDictionary<string, string> BgraHashes =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["Character/pixel_hamster/throw_hit"] = "584b27d59d525c3d0e21d6ed9260a07cbba99f74069a4c95db601dd03cc3fb99",
            ["Character/pixel_cat/throw_hit"] = "c5113a573980ae66ec3f93c05dac75120cdd30c30501ee90d1701876a6c574b7",
            ["Character/pixel_puppy/throw_hit"] = "17b33fe94b2a76791b2d5002f720038ae1299d2185540866110e3258bb9b724a",
            ["Character/pixel_rabbit/throw_hit"] = "5f715868aff1a2606c1f637f35ab1042d4b11f154ce91b5ddf21db33189b55c2",
            ["Character/pixel_penguin/throw_hit"] = "658a54d43d8cd3c8a85b823a1dda11296addf45cad6ce58b7172128882666d0b",
            ["Character/pixel_guinea_pig/throw_hit"] = "d9d96bb33233b9bbe0bf2e8effc6077bdfef978f4c3b61c00124fb8fc0715690",
            ["Character/pixel_monkey/throw_hit"] = "b859c2e4bf6d890070c1ba085f47349771e84514e9ee2e50378da87ac7f0db6a",
            ["Character/pixel_chinchilla/throw_hit"] = "b5bf003b3374a2d26f1c324c71ffbbe8acad54c19d9697861555edf0add0369c",
            ["Character/pixel_starlight_upalupa/throw_hit"] = "3c27f23d45f14da7191850c4ec8c5a99d11d79bf415b0acd9445058e6c1db572",
            ["Throwable/patch_soft_ball/sprite"] = "64d4792b32df1c9dcae113d9a19dcee1f6fc5b6653a8dc4e80ffb1a2793f6e2f",
            ["Throwable/mini_paprika/sprite"] = "1e9f6181ef51c8e0f84f45f1dc12c14bf6141edb132c7131007e8937e969673f",
            ["Throwable/banana/sprite"] = "f42c588b897b5e33b3ca5f676dab15ce9e3aa3be02aad424c6b9ade8d01c372f",
            ["Throwable/dust_bath_pouch/sprite"] = "4d32c76073a8397379c33a42d9ee8e7656f6bf936af343a7d88e6c1d711d2205",
            ["Throwable/starlight_orb/sprite"] = "1719218f94d0686294b56fd836a74700e03312815043e050f0f0dbf4a90ba8ec",
        };

    private readonly Dictionary<string, byte[][]> _actions = new(StringComparer.Ordinal);
    private readonly Dictionary<string, byte[][]> _flippedActions = new(StringComparer.Ordinal);
    private readonly Dictionary<string, byte[][]> _objects = new(StringComparer.Ordinal);
    private bool _disposed;

    internal CharacterThrowFrameCache(
        string characterRoot,
        string throwableRoot,
        int scale,
        OverlayEdge edge)
    {
        foreach (var characterId in ActionHashes.Keys)
        {
            var (normal, flipped) = LoadAction(
                characterRoot,
                characterId,
                ActionHashes[characterId],
                scale,
                edge);
            _actions.Add(characterId, normal);
            _flippedActions.Add(characterId, flipped);
        }
        foreach (var objectId in ObjectHashes.Keys)
        {
            _objects.Add(objectId, LoadSheet(
                Path.Combine(throwableRoot, objectId),
                "sprite",
                $"Throwable/{objectId}/sprite",
                ObjectHashes[objectId],
                cellSize: 16,
                frameCount: ObjectFrameCount,
                scale: scale,
                flip: false,
                edge));
        }
    }

    internal int ObjectPixelSize { get; private set; }

    internal ReadOnlySpan<byte> ActionFrame(string? characterId, int frame, bool flipped)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var id = PixelCharacterCatalog.NormalizeId(characterId);
        var frames = flipped ? _flippedActions[id] : _actions[id];
        return frames[Math.Clamp(frame, 0, ActionFrameCount - 1)];
    }

    internal ReadOnlySpan<byte> ObjectFrame(string? sourceCharacterId, int frame)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var objectId = sourceCharacterId is not null
            && CharacterObjects.TryGetValue(sourceCharacterId, out var mapped)
                ? mapped
                : "patch_soft_ball";
        return _objects[objectId][Math.Clamp(frame, 0, ObjectFrameCount - 1)];
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        foreach (var frame in _actions.Values.SelectMany(value => value)
                     .Concat(_flippedActions.Values.SelectMany(value => value))
                     .Concat(_objects.Values.SelectMany(value => value)))
        {
            Array.Clear(frame);
        }
        _actions.Clear();
        _flippedActions.Clear();
        _objects.Clear();
    }

    private (byte[][] Normal, byte[][] Flipped) LoadAction(
        string characterRoot,
        string characterId,
        string hash,
        int scale,
        OverlayEdge edge)
    {
        var normal = LoadSheet(
            Path.Combine(characterRoot, characterId),
            "throw_hit",
            $"Character/{characterId}/throw_hit",
            hash,
            cellSize: 24,
            frameCount: ActionFrameCount,
            scale: scale,
            flip: false,
            edge);
        var flipped = LoadSheet(
            Path.Combine(characterRoot, characterId),
            "throw_hit",
            $"Character/{characterId}/throw_hit",
            hash,
            cellSize: 24,
            frameCount: ActionFrameCount,
            scale: scale,
            flip: true,
            edge);
        return (normal, flipped);
    }

    private byte[][] LoadSheet(
        string directory,
        string name,
        string resourceId,
        string expectedPngHash,
        int cellSize,
        int frameCount,
        int scale,
        bool flip,
        OverlayEdge edge)
    {
        var png = File.ReadAllBytes(Path.Combine(directory, name + ".png"));
        if (!StringComparer.Ordinal.Equals(
                Convert.ToHexStringLower(SHA256.HashData(png)),
                expectedPngHash))
        {
            throw new InvalidDataException($"{name} throw asset hash does not match the approved manifest.");
        }

        var sheet = File.ReadAllBytes(Path.Combine(directory, name + ".bgra"));
        var expectedLength = checked(cellSize * frameCount * cellSize * 4);
        if (sheet.Length != expectedLength)
        {
            throw new InvalidDataException($"{name} BGRA sheet has an invalid byte length.");
        }
        if (!BgraHashes.TryGetValue(resourceId, out var expectedBgraHash)
            || !StringComparer.Ordinal.Equals(
                Convert.ToHexStringLower(SHA256.HashData(sheet)),
                expectedBgraHash))
        {
            throw new InvalidDataException($"{name} BGRA sheet hash does not match the Windows cache manifest.");
        }

        var frames = new byte[frameCount][];
        for (var frame = 0; frame < frameCount; frame++)
        {
            frames[frame] = BuildFrame(sheet, cellSize, frameCount, frame, scale, flip, edge);
        }
        if (cellSize == 16)
        {
            ObjectPixelSize = cellSize * scale;
        }
        Array.Clear(sheet);
        return frames;
    }

    private static byte[] BuildFrame(
        ReadOnlySpan<byte> sheet,
        int cellSize,
        int frameCount,
        int frame,
        int scale,
        bool flip,
        OverlayEdge edge)
    {
        var sheetWidth = cellSize * frameCount;
        var outputSize = cellSize * scale;
        var output = new byte[outputSize * outputSize * 4];
        for (var y = 0; y < outputSize; y++)
        {
            for (var x = 0; x < outputSize; x++)
            {
                var rotatedX = x / scale;
                var rotatedY = y / scale;
                var (sourceX, sourceY) = InverseRotate(rotatedX, rotatedY, cellSize, edge);
                if (flip)
                {
                    sourceX = cellSize - 1 - sourceX;
                }
                var input = ((sourceY * sheetWidth) + (frame * cellSize) + sourceX) * 4;
                var destination = ((y * outputSize) + x) * 4;
                sheet.Slice(input, 4).CopyTo(output.AsSpan(destination, 4));
            }
        }
        return output;
    }

    private static (int X, int Y) InverseRotate(int x, int y, int size, OverlayEdge edge) =>
        edge switch
        {
            OverlayEdge.Bottom => (x, y),
            OverlayEdge.Top => (size - 1 - x, size - 1 - y),
            OverlayEdge.Left => (y, size - 1 - x),
            OverlayEdge.Right => (size - 1 - y, x),
            _ => throw new ArgumentOutOfRangeException(nameof(edge)),
        };
}
