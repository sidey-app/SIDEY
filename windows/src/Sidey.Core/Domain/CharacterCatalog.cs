namespace Sidey.Core.Domain;

public sealed record PixelCharacterDefinition(
    string Id,
    string DisplayName,
    string SpriteSheetResource,
    string RawBgraResource,
    string ManifestResource,
    string SpriteSheetSha256,
    int FrameWidth,
    int FrameHeight,
    int FrameCount,
    int FootBaselinePixel,
    PixelCharacterFrameContract Frames,
    IReadOnlyList<string> CompatibleAliases);

public sealed record PixelCharacterFrameContract(
    Range Idle,
    Range Walk,
    Range Doze,
    Range Offline)
{
    public static PixelCharacterFrameContract Standard { get; } = new(
        0..2,
        2..6,
        6..8,
        8..10);
}

/// <summary>
/// The only product catalog for built-in Windows characters. Rendering code
/// resolves this data by id and never branches on a species.
/// </summary>
public static class PixelCharacterCatalog
{
    public const string FallbackId = "pixel_hamster";

    private static readonly PixelCharacterDefinition[] Definitions =
    [
        Create(
            FallbackId,
            Localization.I18n.Get("characters.hamster"),
            "43171c1dd614629058b6d593c57ca0e5841b0be03a04a05181dfda67c53a7f45",
            ["minty_pup"]),
        Create(
            "pixel_cat",
            Localization.I18n.Get("characters.cat"),
            "d8b370c03b5cf0ede6aa0d9fa6210030e164b015a920622e89ae86f835e018b2"),
        Create(
            "pixel_puppy",
            Localization.I18n.Get("characters.dog"),
            "8f56a5fda51a224802f41d6d1c359a138c83036b7da3e0a35777f9f4ed38d5f7"),
        Create(
            "pixel_rabbit",
            Localization.I18n.Get("characters.rabbit"),
            "f8e53749200a284f7729ea9baac3237a9fac0caf8efedf9102dcee065e521342"),
        Create(
            "pixel_penguin",
            Localization.I18n.Get("characters.penguin"),
            "f171503f8ffb938732583a4b6f42443e7a69120bb17496f6e8d34372da2ea886"),
    ];

    private static readonly IReadOnlyDictionary<string, PixelCharacterDefinition> ById =
        Definitions.ToDictionary(definition => definition.Id, StringComparer.Ordinal);

    private static readonly IReadOnlyDictionary<string, string> AliasToId = Definitions
        .SelectMany(definition => definition.CompatibleAliases.Select(alias => (alias, definition.Id)))
        .ToDictionary(pair => pair.alias, pair => pair.Id, StringComparer.Ordinal);

    public static IReadOnlyList<PixelCharacterDefinition> All => Definitions;

    public static PixelCharacterDefinition Fallback => ById[FallbackId];

    public static string NormalizeId(string? characterId)
    {
        if (characterId is not null && ById.ContainsKey(characterId))
        {
            return characterId;
        }

        return characterId is not null && AliasToId.TryGetValue(characterId, out var canonical)
            ? canonical
            : FallbackId;
    }

    public static PixelCharacterDefinition Get(string? characterId) => ById[NormalizeId(characterId)];

    private static PixelCharacterDefinition Create(
        string id,
        string displayName,
        string spriteSheetSha256,
        IReadOnlyList<string>? aliases = null) => new(
            id,
            displayName,
            $"Characters/{id}/sprite.png",
            $"Characters/{id}/frames.bgra",
            $"Characters/{id}/manifest.json",
            spriteSheetSha256,
            FrameWidth: 24,
            FrameHeight: 24,
            FrameCount: 10,
            FootBaselinePixel: 3,
            Frames: PixelCharacterFrameContract.Standard,
            CompatibleAliases: aliases ?? Array.Empty<string>());
}
