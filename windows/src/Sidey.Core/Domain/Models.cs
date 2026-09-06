namespace Sidey.Core.Domain;

public enum PresenceState
{
    Online,
    Typing,
    Away,
    Offline,
    Reconnecting,
}

public enum OverlayEdge
{
    Bottom,
    Left,
    Right,
    Top,
}

public enum OverlaySpan
{
    Third,
    Half,
    Full,
}

public static class OverlaySpanExtensions
{
    public static double Fraction(this OverlaySpan span) => span switch
    {
        OverlaySpan.Third => 1d / 3d,
        OverlaySpan.Half => 1d / 2d,
        OverlaySpan.Full => 1d,
        _ => throw new ArgumentOutOfRangeException(nameof(span)),
    };
}

public sealed record Profile(
    Guid Id,
    string Nickname,
    string CharacterId,
    string? EquippedBubbleStyleId = null,
    string? EquippedThrowableId = null);

public sealed record RoomMember(
    Guid UserId,
    string Nickname,
    string CharacterId,
    PresenceState Presence,
    string? EquippedBubbleStyleId = null);

public sealed record Room(
    Guid Id,
    string Name,
    Guid OwnerId,
    IReadOnlyList<RoomMember> Members,
    string InviteCodeHint,
    bool InviteCodeReady,
    long RealtimeEpoch);

public sealed record ChatMessage(
    Guid Id,
    Guid RoomId,
    Guid SenderId,
    string Body,
    DateTimeOffset CreatedAt,
    string? BubbleStyleId = null);

public sealed record PixelWorldMember(
    Guid Id,
    string Nickname,
    string CharacterId,
    PresenceState Presence,
    bool IsTyping,
    bool IsCurrentUser,
    string? EquippedBubbleStyleId = null);

public sealed record CharacterPulseEvent(Guid Id, Guid RoomId, Guid UserId);

public sealed record CharacterThrowEvent(
    Guid Id,
    Guid RoomId,
    Guid ActorUserId,
    Guid TargetUserId,
    string SourceCharacterId,
    string? ThrowableId = null);

public enum CommerceProductKind
{
    Character,
    Bubble,
    Throwable,
}

public enum CommercePurchaseState
{
    Unavailable,
    GoogleConnectionRequired,
    Available,
    OpeningCheckout,
    Confirming,
    Owned,
    Refunded,
    Error,
}

public sealed record CommerceProduct(
    string Id,
    string CharacterId,
    string EntitlementKey,
    int SortOrder,
    int AmountKrw,
    CommerceProductKind Kind = CommerceProductKind.Character,
    string? CatalogItemId = null)
{
    public string EffectiveCatalogItemId => CatalogItemId ?? CharacterId;
}

public sealed record CommerceProductState(
    CommerceProduct Product,
    bool GoogleConnected,
    CommercePurchaseState PurchaseState,
    bool IsWorking = false,
    string? ErrorMessage = null);

public static class WindowsCommerceCatalog
{
    public static IReadOnlyList<CommerceProduct> Products { get; } =
    [
        new(
            "character_starlight_upalupa",
            "pixel_starlight_upalupa",
            "character:pixel_starlight_upalupa",
            10,
            1_900),
        new(
            "character_guinea_pig",
            "pixel_guinea_pig",
            "character:pixel_guinea_pig",
            20,
            990),
        new(
            "character_monkey",
            "pixel_monkey",
            "character:pixel_monkey",
            30,
            990),
        new(
            "character_chinchilla",
            "pixel_chinchilla",
            "character:pixel_chinchilla",
            40,
            990),
        new(
            "bubble_bunny_pink",
            "pixel_hamster",
            "bubble:bubble_bunny_pink",
            110,
            1_900,
            CommerceProductKind.Bubble,
            "bubble_bunny_pink"),
        new(
            "bubble_butter_chick",
            "pixel_hamster",
            "bubble:bubble_butter_chick",
            120,
            1_900,
            CommerceProductKind.Bubble,
            "bubble_butter_chick"),
        new(
            "bubble_starry_cat",
            "pixel_hamster",
            "bubble:bubble_starry_cat",
            130,
            1_900,
            CommerceProductKind.Bubble,
            "bubble_starry_cat"),
        new(
            "throwable_bouncy_heart",
            "pixel_hamster",
            "throwable:throwable_bouncy_heart",
            210,
            990,
            CommerceProductKind.Throwable,
            "throwable_bouncy_heart"),
        new(
            "throwable_toy_cannon",
            "pixel_hamster",
            "throwable:throwable_toy_cannon",
            220,
            2_900,
            CommerceProductKind.Throwable,
            "throwable_toy_cannon"),
        new(
            "throwable_squeaky_duck",
            "pixel_hamster",
            "throwable:throwable_squeaky_duck",
            230,
            990,
            CommerceProductKind.Throwable,
            "throwable_squeaky_duck"),
    ];

    public static CommerceProduct? Find(string productId) =>
        Products.FirstOrDefault(product =>
            StringComparer.Ordinal.Equals(product.Id, productId));

    public static IReadOnlyList<CommerceProductState> LockedStates() =>
        Products.Select(product => new CommerceProductState(
            product,
            GoogleConnected: false,
            CommercePurchaseState.Unavailable)).ToArray();
}

public static class CharacterThrowTargetPolicy
{
    public static bool CanTarget(PixelWorldMember member) => !member.IsCurrentUser;
}

public sealed record ActiveBubble(
    Guid SenderId,
    Guid MessageId,
    string Body,
    DateTimeOffset ExpiresAt,
    string? BubbleStyleId = null);

public static class CosmeticCatalog
{
    public static IReadOnlySet<string> BubbleStyleIds { get; } = new HashSet<string>(
        WindowsCommerceCatalog.Products
            .Where(product => product.Kind == CommerceProductKind.Bubble)
            .Select(product => product.EffectiveCatalogItemId),
        StringComparer.Ordinal);

    public static IReadOnlySet<string> ThrowableIds { get; } = new HashSet<string>(
        WindowsCommerceCatalog.Products
            .Where(product => product.Kind == CommerceProductKind.Throwable)
            .Select(product => product.EffectiveCatalogItemId),
        StringComparer.Ordinal);

    public static string? NormalizeBubbleStyleId(string? id) =>
        id is not null && BubbleStyleIds.Contains(id) ? id : null;

    public static string? NormalizeThrowableId(string? id) =>
        id is not null && ThrowableIds.Contains(id) ? id : null;
}

public sealed record OverlayRegionPreference(
    OverlayEdge Edge,
    OverlaySpan Span,
    string? MonitorIdentifier)
{
    public static OverlayRegionPreference Default { get; } =
        new(OverlayEdge.Bottom, OverlaySpan.Full, null);
}

public sealed record WorldSnapshot(
    Guid? RoomId,
    IReadOnlyList<PixelWorldMember> Members,
    IReadOnlyList<ActiveBubble> Bubbles,
    IReadOnlyList<CharacterPulseEvent> Pulses,
    IReadOnlyList<CharacterThrowEvent> Throws,
    OverlayEdge Edge,
    long InstallationSeed);
