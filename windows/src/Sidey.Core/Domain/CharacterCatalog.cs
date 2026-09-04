namespace Sidey.Core.Domain;

public enum PixelCharacterVisualEffect
{
    None,
    StarlightSparkles,
}

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
    string? EntitlementKey,
    PixelCharacterVisualEffect VisualEffect,
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
        Create(
            "pixel_guinea_pig",
            Localization.I18n.Get("characters.guineaPig"),
            "1a0bf85dae86f2e6bb460e8b0b852c2bd010d5ff6f7efd1477cbd6986da64f5b",
            entitlementKey: "character:pixel_guinea_pig"),
        Create(
            "pixel_monkey",
            Localization.I18n.Get("characters.monkey"),
            "515fe377f5344dd4cbaa2b0faf58de3ce72fdc62be5aff6a9d9de683983c783b",
            entitlementKey: "character:pixel_monkey"),
        Create(
            "pixel_chinchilla",
            Localization.I18n.Get("characters.chinchilla"),
            "c0009e007a7a63029fb58ad6f94d2b9a8c9ae7a55f139dd4892050f11614c5d4",
            ["pixel_koala"],
            "character:pixel_chinchilla"),
        Create(
            "pixel_starlight_upalupa",
            Localization.I18n.Get("characters.starlightUpalupa"),
            "d180810a8796280077f3f70f6da681888c583c2f8d74776d0f5d300e943a079a",
            entitlementKey: "character:pixel_starlight_upalupa",
            visualEffect: PixelCharacterVisualEffect.StarlightSparkles),
    ];

    private static readonly PixelCharacterDefinition[] SelectableDefinitions = Definitions[..5];

    private static readonly IReadOnlyDictionary<string, PixelCharacterDefinition> ById =
        Definitions.ToDictionary(definition => definition.Id, StringComparer.Ordinal);

    private static readonly IReadOnlyDictionary<string, string> AliasToId = Definitions
        .SelectMany(definition => definition.CompatibleAliases.Select(alias => (alias, definition.Id)))
        .ToDictionary(pair => pair.alias, pair => pair.Id, StringComparer.Ordinal);

    public static IReadOnlyList<PixelCharacterDefinition> All => Definitions;

    /// <summary>
    /// Characters that every account can select without an entitlement.
    /// </summary>
    public static IReadOnlyList<PixelCharacterDefinition> Selectable => SelectableDefinitions;

    public static IReadOnlyList<PixelCharacterDefinition> SelectableFor(
        IReadOnlySet<string> activeEntitlementKeys)
    {
        ArgumentNullException.ThrowIfNull(activeEntitlementKeys);
        return Definitions
            .Where(definition => definition.EntitlementKey is null
                || activeEntitlementKeys.Contains(definition.EntitlementKey))
            .ToArray();
    }

    public static IReadOnlySet<string> ResolveActiveEntitlementKeys(
        IReadOnlySet<string>? remoteKeys,
        string? profileCharacterId)
    {
        if (remoteKeys is not null)
        {
            return new HashSet<string>(remoteKeys, StringComparer.Ordinal);
        }

        string? entitlementKey = Get(profileCharacterId).EntitlementKey;
        return entitlementKey is null
            ? new HashSet<string>(StringComparer.Ordinal)
            : new HashSet<string>([entitlementKey], StringComparer.Ordinal);
    }

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

    public static bool CanSelect(
        string? characterId,
        IReadOnlySet<string> activeEntitlementKeys)
    {
        ArgumentNullException.ThrowIfNull(activeEntitlementKeys);
        PixelCharacterDefinition definition = Get(characterId);
        return definition.EntitlementKey is null
            || activeEntitlementKeys.Contains(definition.EntitlementKey);
    }

    public static string SelectableId(
        string? characterId,
        IReadOnlySet<string> activeEntitlementKeys) =>
        CanSelect(characterId, activeEntitlementKeys)
            ? NormalizeId(characterId)
            : FallbackId;

    private static PixelCharacterDefinition Create(
        string id,
        string displayName,
        string spriteSheetSha256,
        IReadOnlyList<string>? aliases = null,
        string? entitlementKey = null,
        PixelCharacterVisualEffect visualEffect = PixelCharacterVisualEffect.None) => new(
            id,
            displayName,
            $"Character/{id}/base.png",
            $"Character/{id}/base.bgra",
            $"Character/{id}/manifest.json",
            spriteSheetSha256,
            FrameWidth: 24,
            FrameHeight: 24,
            FrameCount: 10,
            FootBaselinePixel: 3,
            Frames: PixelCharacterFrameContract.Standard,
            EntitlementKey: entitlementKey,
            VisualEffect: visualEffect,
            CompatibleAliases: aliases ?? Array.Empty<string>());
}
