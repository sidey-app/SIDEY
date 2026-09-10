namespace Sidey.Core.Domain;

public static class ImpactSoundCatalog
{
    public static IReadOnlyList<string> Ids { get; } = Array.AsReadOnly(new[]
    {
        "patch_soft_ball", "mini_paprika", "banana", "dust_bath_pouch", "starlight_orb",
        "throwable_bouncy_heart", "throwable_squeaky_duck", "throwable_toy_cannon",
    });

    public static string Resolve(string characterId, string? equippedId)
    {
        if (equippedId is not null && Ids.Contains(equippedId))
            return equippedId;
        return PixelCharacterCatalog.NormalizeId(characterId) switch
        {
            "pixel_guinea_pig" => "mini_paprika",
            "pixel_monkey" => "banana",
            "pixel_chinchilla" => "dust_bath_pouch",
            "pixel_starlight_upalupa" => "starlight_orb",
            _ => "patch_soft_ball",
        };
    }
}
