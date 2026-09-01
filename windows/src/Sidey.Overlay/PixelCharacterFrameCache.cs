using Sidey.Core.Domain;
using System.Security.Cryptography;

namespace Sidey.Overlay;

internal sealed record CachedCharacterFrames(
    PixelCharacterDefinition Definition,
    int PixelSize,
    byte[][] Normal,
    byte[][] Flipped)
{
    public ReadOnlySpan<byte> Frame(int index, bool flipped) =>
        (flipped ? Flipped : Normal)[index];
}

internal sealed class PixelCharacterFrameCache : IDisposable
{
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

        var requested = characterIds is null
            ? PixelCharacterCatalog.All.Select(definition => definition.Id).ToHashSet(StringComparer.Ordinal)
            : characterIds.Select(PixelCharacterCatalog.NormalizeId).ToHashSet(StringComparer.Ordinal);
        _entries = new Dictionary<string, CachedCharacterFrames>(StringComparer.Ordinal);
        foreach (var definition in PixelCharacterCatalog.All.Where(item => requested.Contains(item.Id)))
        {
            var pngPath = Path.Combine(assetRoot, Path.GetFileName(definition.SpriteSheetResource));
            var png = File.ReadAllBytes(pngPath);
            var hash = Convert.ToHexStringLower(SHA256.HashData(png));
            if (!StringComparer.Ordinal.Equals(hash, definition.SpriteSheetSha256))
            {
                throw new InvalidDataException($"{definition.Id} sprite hash does not match its catalog entry.");
            }

            var rawPath = Path.Combine(assetRoot, Path.GetFileName(definition.RawBgraResource));
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
                    integerScale,
                    flipHorizontally: false,
                    edge);
                flipped[frame] = PremultipliedBgraFrameBuilder.BuildFrame(
                    sheet,
                    definition,
                    frame,
                    integerScale,
                    flipHorizontally: true,
                    edge);
            }

            _entries.Add(
                definition.Id,
                new CachedCharacterFrames(
                    definition,
                    definition.FrameWidth * integerScale,
                    normal,
                    flipped));
        }

        if (_entries.Count == 0)
        {
            throw new InvalidOperationException("At least one SIDEY character must be cached.");
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

        return _entries.TryGetValue(PixelCharacterCatalog.FallbackId, out var fallback)
            ? fallback
            : _entries.Values.First();
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
        _entries.Clear();
    }
}
