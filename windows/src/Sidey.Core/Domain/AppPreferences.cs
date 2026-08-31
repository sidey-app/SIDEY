namespace Sidey.Core.Domain;

public sealed record AppPreferences(
    bool OverlayVisible,
    bool QuietMode,
    bool ShowOfflineMembers,
    bool StartAtLogin,
    Guid? ActiveRoomId,
    OverlayRegionPreference OverlayRegion)
{
    public static AppPreferences Default { get; } = new(
        OverlayVisible: true,
        QuietMode: false,
        ShowOfflineMembers: true,
        StartAtLogin: false,
        ActiveRoomId: null,
        OverlayRegion: OverlayRegionPreference.Default);
}
