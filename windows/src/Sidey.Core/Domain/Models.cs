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

public sealed record Profile(Guid Id, string Nickname, string CharacterId);

public sealed record RoomMember(
    Guid UserId,
    string Nickname,
    string CharacterId,
    PresenceState Presence);

public sealed record Room(
    Guid Id,
    string Name,
    Guid OwnerId,
    IReadOnlyList<RoomMember> Members,
    string InviteCodeHint,
    int InviteVersion);

public sealed record ChatMessage(
    Guid Id,
    Guid RoomId,
    Guid SenderId,
    string Body,
    DateTimeOffset CreatedAt);

public sealed record PixelWorldMember(
    Guid Id,
    string Nickname,
    string CharacterId,
    PresenceState Presence,
    bool IsTyping,
    bool IsCurrentUser);

public sealed record CharacterPulseEvent(Guid Id, Guid RoomId, Guid UserId);

public sealed record ActiveBubble(
    Guid SenderId,
    Guid MessageId,
    string Body,
    DateTimeOffset ExpiresAt);

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
    OverlayEdge Edge,
    long InstallationSeed);
