using Sidey.Core.Domain;

namespace Sidey.Core.Tests;

public sealed class AppPreferencesTests
{
    [Fact]
    public void DefaultContainsEveryPersistedWindowsSettingAndStartupStaysOff()
    {
        var preferences = AppPreferences.CreateDefault(1234);

        Assert.Equal(AppPreferences.CurrentSchemaVersion, preferences.SchemaVersion);
        Assert.False(preferences.OnboardingCompleted);
        Assert.Equal(1234, preferences.InstallationSeed);
        Assert.True(preferences.OverlayVisible);
        Assert.False(preferences.QuietMode);
        Assert.True(preferences.ShowOfflineMembers);
        Assert.False(preferences.StartAtLogin);
        Assert.Null(preferences.ActiveRoomId);
        Assert.Equal(OverlayRegionPreference.Default, preferences.OverlayRegion);
    }
}
