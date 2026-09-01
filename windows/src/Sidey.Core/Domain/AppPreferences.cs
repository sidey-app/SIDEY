namespace Sidey.Core.Domain;

public sealed record AppPreferences(
    int SchemaVersion,
    bool OnboardingCompleted,
    long InstallationSeed,
    bool OverlayVisible,
    bool QuietMode,
    bool ShowOfflineMembers,
    bool StartAtLogin,
    Guid? ActiveRoomId,
    OverlayRegionPreference OverlayRegion)
{
    public const int CurrentSchemaVersion = 1;

    public static AppPreferences CreateDefault(long? installationSeed = null) => new(
        SchemaVersion: CurrentSchemaVersion,
        OnboardingCompleted: false,
        InstallationSeed: installationSeed ?? Random.Shared.NextInt64(),
        OverlayVisible: true,
        QuietMode: false,
        ShowOfflineMembers: true,
        StartAtLogin: false,
        ActiveRoomId: null,
        OverlayRegion: OverlayRegionPreference.Default);

    public static AppPreferences Default { get; } = CreateDefault(0x51DE7);

    public AppPreferences Normalize() => this with
    {
        SchemaVersion = CurrentSchemaVersion,
        InstallationSeed = InstallationSeed == 0 ? Random.Shared.NextInt64() : InstallationSeed,
        OverlayRegion = OverlayRegion ?? OverlayRegionPreference.Default,
    };
}
