using Sidey.Core.Domain;

namespace Sidey.Core.Overlay;

public static class CachedStartupWorld
{
    // Presentation-only identity. Never used as a profile, room membership or broadcast sender.
    private static readonly Guid LocalCharacterId = new("7d7df25e-225c-4a2d-8643-4b6681d598c1");

    public static WorldSnapshot? Create(AppPreferences preferences)
    {
        if (!preferences.OnboardingCompleted || !preferences.OverlayVisible
            || preferences.CachedNickname is not { } nickname || !ProfileValidator.IsValidNickname(nickname))
            return null;
        return new WorldSnapshot(null,
            [new PixelWorldMember(LocalCharacterId, ProfileValidator.NormalizeNickname(nickname),
                PixelCharacterCatalog.NormalizeId(preferences.CachedCharacterId), PresenceState.Reconnecting, false, true)],
            [], [], [], preferences.OverlayRegion.Edge, preferences.InstallationSeed);
    }
}
