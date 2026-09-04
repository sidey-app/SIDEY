using System.Security.Cryptography;
using Sidey.Core.Domain;

namespace Sidey.Overlay;

internal readonly record struct PixelContentBounds(int MinX, int MinY, int MaxX, int MaxY);

internal sealed record CachedCharacterFrames(
    PixelCharacterDefinition Definition,
    int PixelSize,
    PixelContentBounds OnlineContentBounds,
    byte[][] Normal,
    byte[][] Flipped)
{
    public ReadOnlySpan<byte> Frame(int index, bool flipped) =>
        (flipped ? Flipped : Normal)[index];
}

internal sealed class PixelCharacterFrameCache : IDisposable
{
    private readonly string _assetRoot;
    private readonly int _integerScale;
    private readonly OverlayEdge _edge;
    private readonly Dictionary<string, CachedCharacterFrames> _entries;
    private bool _disposed;

    public PixelCharacterFrameCache(
        string assetRoot,
        int integerScale,
        OverlayEdge edge,
        IReadOnlySet<string>? characterIds = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(assetRoot);
        if (integerScale <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(integerScale));
        }

        _assetRoot = assetRoot;
        _integerScale = integerScale;
        _edge = edge;
        _entries = new Dictionary<string, CachedCharacterFrames>(StringComparer.Ordinal);
        if (characterIds is null)
        {
            return;
        }

        foreach (string characterId in characterIds
                     .Select(PixelCharacterCatalog.NormalizeId)
                     .Distinct(StringComparer.Ordinal))
        {
            _entries.Add(characterId, Load(characterId));
        }
    }

    public CachedCharacterFrames Get(string? characterId)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var normalized = PixelCharacterCatalog.NormalizeId(characterId);
        if (_entries.TryGetValue(normalized, out var entry))
        {
            return entry;
        }

        entry = Load(normalized);
        _entries.Add(normalized, entry);
        return entry;
    }

    public void RetainCharacters(IEnumerable<string?> characterIds)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        ArgumentNullException.ThrowIfNull(characterIds);
        var retained = characterIds
            .Select(PixelCharacterCatalog.NormalizeId)
            .ToHashSet(StringComparer.Ordinal);
        foreach (string characterId in _entries.Keys.Where(id => !retained.Contains(id)).ToArray())
        {
            ClearFrames(_entries[characterId]);
            _entries.Remove(characterId);
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        foreach (var entry in _entries.Values)
        {
            ClearFrames(entry);
        }
        _entries.Clear();
    }

    private static void ClearFrames(CachedCharacterFrames entry)
    {
        foreach (var frame in entry.Normal)
        {
            Array.Clear(frame);
        }
        foreach (var frame in entry.Flipped)
        {
            Array.Clear(frame);
        }
        Array.Clear(entry.Normal);
        Array.Clear(entry.Flipped);
    }

    private static string ResolveAssetPath(string assetRoot, string catalogResource)
    {
        const string catalogPrefix = "Character/";
        var relativePath = catalogResource.StartsWith(catalogPrefix, StringComparison.Ordinal)
            ? catalogResource[catalogPrefix.Length..]
            : catalogResource;
        return Path.Combine(assetRoot, relativePath.Replace('/', Path.DirectorySeparatorChar));
    }

    private CachedCharacterFrames Load(string characterId)
    {
        PixelCharacterDefinition definition = PixelCharacterCatalog.All.First(
            candidate => StringComparer.Ordinal.Equals(candidate.Id, characterId));
        var pngPath = ResolveAssetPath(_assetRoot, definition.SpriteSheetResource);
        var png = File.ReadAllBytes(pngPath);
        var hash = Convert.ToHexStringLower(SHA256.HashData(png));
        if (!StringComparer.Ordinal.Equals(hash, definition.SpriteSheetSha256))
        {
            throw new InvalidDataException($"{definition.Id} sprite hash does not match its catalog entry.");
        }

        var rawPath = ResolveAssetPath(_assetRoot, definition.RawBgraResource);
        var sheet = File.ReadAllBytes(rawPath);
        var expectedLength = checked(
            definition.FrameWidth
            * definition.FrameCount
            * definition.FrameHeight
            * 4);
        if (sheet.Length != expectedLength)
        {
            throw new InvalidDataException(
                $"{definition.Id} BGRA sheet must contain {expectedLength} bytes, found {sheet.Length}.");
        }

        var normal = new byte[definition.FrameCount][];
        var flipped = new byte[definition.FrameCount][];
        for (var frame = 0; frame < definition.FrameCount; frame++)
        {
            normal[frame] = PremultipliedBgraFrameBuilder.BuildFrame(
                sheet,
                definition,
                frame,
                _integerScale,
                flipHorizontally: false,
                _edge);
            flipped[frame] = PremultipliedBgraFrameBuilder.BuildFrame(
                sheet,
                definition,
                frame,
                _integerScale,
                flipHorizontally: true,
                _edge);
        }

        return new CachedCharacterFrames(
            definition,
            definition.FrameWidth * _integerScale,
            FindOnlineContentBounds(
                normal,
                flipped,
                definition,
                definition.FrameWidth * _integerScale),
            normal,
            flipped);
    }

    private static PixelContentBounds FindOnlineContentBounds(
        byte[][] normal,
        byte[][] flipped,
        PixelCharacterDefinition definition,
        int size)
    {
        var minX = size;
        var minY = size;
        var maxX = 0;
        var maxY = 0;
        foreach (var frameIndex in FrameIndexes(definition.Frames.Idle)
                     .Concat(FrameIndexes(definition.Frames.Walk)))
        {
            foreach (var frame in new[] { normal[frameIndex], flipped[frameIndex] })
            {
                for (var y = 0; y < size; y++)
                {
                    for (var x = 0; x < size; x++)
                    {
                        if (frame[((y * size) + x) * 4 + 3] == 0)
                        {
                            continue;
                        }

                        minX = Math.Min(minX, x);
                        minY = Math.Min(minY, y);
                        maxX = Math.Max(maxX, x + 1);
                        maxY = Math.Max(maxY, y + 1);
                    }
                }
            }
        }

        return minX < maxX && minY < maxY
            ? new PixelContentBounds(minX, minY, maxX, maxY)
            : new PixelContentBounds(0, 0, size, size);
    }

    private static IEnumerable<int> FrameIndexes(Range range) =>
        Enumerable.Range(range.Start.Value, range.End.Value - range.Start.Value);
}
