using Sidey.Core.Domain;
using Sidey.Core.Overlay;
using Sidey.Core.Realtime;

namespace Sidey.Core.Tests;

public sealed class CachedStartupWorldTests
{
    private static AppPreferences Saved => AppPreferences.Default with
    {
        OnboardingCompleted = true,
        CachedNickname = "모카",
        CachedCharacterId = "pixel_cat",
        ActiveRoomId = Guid.NewGuid(),
        ShowOfflineMembers = false,
    };

    [Fact]
    public void CachedSelfWaitsForConnectionWithoutCreatingARoomOrLiveActions()
    {
        AppPreferences preferences = Saved;
        WorldSnapshot world = Assert.IsType<WorldSnapshot>(CachedStartupWorld.Create(preferences));
        PixelWorldMember self = Assert.Single(world.Members);
        Assert.Equal("모카", self.Nickname);
        Assert.Equal("pixel_cat", self.CharacterId);
        Assert.Equal(PresenceState.Reconnecting, self.Presence);
        Assert.True(self.IsCurrentUser);
        Assert.False(self.IsTyping);
        Assert.Null(world.RoomId);
        Assert.Empty(world.Bubbles);
        Assert.Empty(world.Pulses);
        Assert.Empty(world.Throws);
        Assert.Equal(self.Id, Assert.Single(CachedStartupWorld.Create(preferences)!.Members).Id);
    }

    [Fact]
    public void HiddenOverlayAndIncompleteOnboardingDoNotCreateAStartupCharacter()
    {
        Assert.Null(CachedStartupWorld.Create(Saved with { OverlayVisible = false }));
        Assert.Null(CachedStartupWorld.Create(Saved with { OnboardingCompleted = false }));
        Assert.Null(CachedStartupWorld.Create(Saved with { CachedNickname = null }));
        Assert.Null(CachedStartupWorld.Create(Saved with { CachedNickname = "x" }));
    }

    [Fact]
    public void CachedPaidCharactersAndSavedGeometryUseTheSharedCatalog()
    {
        foreach (PixelCharacterDefinition character in PixelCharacterCatalog.All)
            foreach (OverlayEdge edge in Enum.GetValues<OverlayEdge>())
            {
                AppPreferences preferences = Saved with
                {
                    CachedCharacterId = character.Id,
                    OverlayRegion = OverlayRegionPreference.Default with { Edge = edge }
                };
                WorldSnapshot world = CachedStartupWorld.Create(preferences)!;
                Assert.Equal(character.Id, Assert.Single(world.Members).CharacterId);
                Assert.Equal(edge, world.Edge);
                Assert.Equal(preferences.InstallationSeed, world.InstallationSeed);
            }
    }

    [Theory]
    [InlineData(PresenceState.Online)]
    [InlineData(PresenceState.Away)]
    [InlineData(PresenceState.Typing)]
    [InlineData(PresenceState.Offline)]
    public void SnapshotCannotShowOnlineBeforeActiveRoomTransportConnects(PresenceState presence)
    {
        Assert.Equal(PresenceState.Reconnecting, LocalPresenceProjection.ForOverlay(presence, false));
        Assert.Equal(presence, LocalPresenceProjection.ForOverlay(presence, true));
        Assert.Equal(PresenceState.Reconnecting, LocalPresenceProjection.ForOverlay(PresenceState.Reconnecting, false));
    }
}
