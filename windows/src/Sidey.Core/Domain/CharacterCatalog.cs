namespace Sidey.Core.Domain;

public sealed record PixelCharacterDefinition(
    string Id,
    string DisplayName,
    string SpriteSheetResource,
    int FrameWidth,
    int FrameHeight,
    int FrameCount,
    int FootBaselinePixel,
    PixelCharacterFrameContract Frames);

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

public static class VerticalSliceCharacterCatalog
{
    public const string HamsterId = "pixel_hamster";

    public static PixelCharacterDefinition Hamster { get; } = new(
        HamsterId,
        "햄스터",
        "Characters/pixel_hamster.png",
        FrameWidth: 24,
        FrameHeight: 24,
        FrameCount: 10,
        FootBaselinePixel: 3,
        Frames: PixelCharacterFrameContract.Standard);

    public static string NormalizeId(string? characterId) => characterId switch
    {
        HamsterId or "minty_pup" => HamsterId,
        _ => HamsterId,
    };
}
