using Sidey.Core.Abstractions;
using Sidey.Core.Domain;

namespace Sidey.Platform.Windows.Tests;

public sealed class GlobalShortcutCoordinatorTests
{
    private static readonly GlobalShortcut s_compose =
        new(GlobalShortcutModifiers.Control | GlobalShortcutModifiers.Shift, 0x4D);
    private static readonly GlobalShortcut s_overlay =
        new(GlobalShortcutModifiers.Alt | GlobalShortcutModifiers.Shift, 0x4F);
    private static readonly GlobalShortcut s_replacement =
        new(GlobalShortcutModifiers.Alt | GlobalShortcutModifiers.Shift, 0x4D);

    [Fact]
    public async Task SavedShortcutsRegisterOnAttachAndFailuresStaySaved()
    {
        var preferences = new MemoryPreferences(AppPreferences.Default with
        {
            GlobalShortcuts = GlobalShortcutPreferences.Empty
                .With(GlobalShortcutAction.Compose, s_compose)
                .With(GlobalShortcutAction.ToggleOverlay, s_overlay),
        });
        var registrar = new FakeRegistrar();
        registrar.Results[s_overlay] = GlobalShortcutRegistrationStatus.InUse;
        await using var coordinator = new AppCoordinator(preferences);
        await coordinator.LoadCachedStateAsync();

        coordinator.AttachGlobalShortcuts(registrar);

        Assert.Equal(GlobalShortcutRegistrationStatus.Registered, coordinator.State.GlobalShortcutStatuses[GlobalShortcutAction.Compose]);
        Assert.Equal(GlobalShortcutRegistrationStatus.InUse, coordinator.State.GlobalShortcutStatuses[GlobalShortcutAction.ToggleOverlay]);
        Assert.Equal(GlobalShortcutRegistrationStatus.NotSet, coordinator.State.GlobalShortcutStatuses[GlobalShortcutAction.ToggleQuietMode]);
        Assert.Equal(s_overlay, coordinator.State.Preferences.GlobalShortcuts.Get(GlobalShortcutAction.ToggleOverlay));
        Assert.Equal(0, preferences.SaveCount);
    }

    [Fact]
    public async Task MissingRegistrarReportsSavedShortcutsAsUnavailable()
    {
        var preferences = new MemoryPreferences(AppPreferences.Default with
        {
            GlobalShortcuts = GlobalShortcutPreferences.Empty.With(GlobalShortcutAction.Compose, s_compose),
        });
        await using var coordinator = new AppCoordinator(preferences);
        await coordinator.LoadCachedStateAsync();

        coordinator.AttachGlobalShortcuts(null);

        Assert.Equal(GlobalShortcutRegistrationStatus.Unavailable, coordinator.State.GlobalShortcutStatuses[GlobalShortcutAction.Compose]);
        Assert.Equal(
            GlobalShortcutRegistrationStatus.Unavailable,
            await coordinator.SetGlobalShortcutAsync(GlobalShortcutAction.ToggleOverlay, s_overlay));
        Assert.Null(coordinator.State.Preferences.GlobalShortcuts.ToggleOverlay);
    }

    [Fact]
    public async Task ChangesAreSavedOnlyAfterWindowsAcceptsTheCombination()
    {
        var preferences = new MemoryPreferences(AppPreferences.Default with
        {
            GlobalShortcuts = GlobalShortcutPreferences.Empty.With(GlobalShortcutAction.Compose, s_compose),
        });
        var registrar = new FakeRegistrar();
        await using var coordinator = new AppCoordinator(preferences);
        await coordinator.LoadCachedStateAsync();
        coordinator.AttachGlobalShortcuts(registrar);

        registrar.Results[s_replacement] = GlobalShortcutRegistrationStatus.InUse;
        GlobalShortcutRegistrationStatus conflict =
            await coordinator.SetGlobalShortcutAsync(GlobalShortcutAction.Compose, s_replacement);

        Assert.Equal(GlobalShortcutRegistrationStatus.InUse, conflict);
        Assert.Equal(s_compose, coordinator.State.Preferences.GlobalShortcuts.Get(GlobalShortcutAction.Compose));
        Assert.Equal(GlobalShortcutRegistrationStatus.Registered, coordinator.State.GlobalShortcutStatuses[GlobalShortcutAction.Compose]);
        Assert.Equal(0, preferences.SaveCount);

        registrar.Results.Remove(s_replacement);
        Assert.Equal(
            GlobalShortcutRegistrationStatus.Registered,
            await coordinator.SetGlobalShortcutAsync(GlobalShortcutAction.Compose, s_replacement));
        Assert.Equal(
            GlobalShortcutRegistrationStatus.NotSet,
            await coordinator.SetGlobalShortcutAsync(GlobalShortcutAction.ToggleOverlay, null));

        Assert.Equal("Alt+Shift+M", preferences.Saved.GlobalShortcuts.Compose);
        Assert.Equal(1, preferences.SaveCount);
    }

    [Fact]
    public async Task SaveFailureRestoresThePreviousRegistration()
    {
        var preferences = new MemoryPreferences(AppPreferences.Default with
        {
            GlobalShortcuts = GlobalShortcutPreferences.Empty.With(GlobalShortcutAction.Compose, s_compose),
        });
        var registrar = new FakeRegistrar();
        await using var coordinator = new AppCoordinator(preferences);
        await coordinator.LoadCachedStateAsync();
        coordinator.AttachGlobalShortcuts(registrar);
        preferences.FailSaves = true;

        await Assert.ThrowsAsync<IOException>(() =>
            coordinator.SetGlobalShortcutAsync(GlobalShortcutAction.Compose, s_replacement));

        Assert.Equal(s_compose, coordinator.State.Preferences.GlobalShortcuts.Get(GlobalShortcutAction.Compose));
        Assert.Equal((GlobalShortcutAction.Compose, (GlobalShortcut?)s_compose), registrar.Calls[^1]);
        Assert.Equal(GlobalShortcutRegistrationStatus.Registered, coordinator.State.GlobalShortcutStatuses[GlobalShortcutAction.Compose]);
    }

    [Fact]
    public async Task InvalidOrRepeatedCombinationsAreRejected()
    {
        var preferences = new MemoryPreferences(AppPreferences.Default with
        {
            GlobalShortcuts = GlobalShortcutPreferences.Empty.With(GlobalShortcutAction.Compose, s_compose),
        });
        var registrar = new FakeRegistrar();
        await using var coordinator = new AppCoordinator(preferences);
        await coordinator.LoadCachedStateAsync();
        coordinator.AttachGlobalShortcuts(registrar);
        int registrations = registrar.Calls.Count;

        await Assert.ThrowsAsync<ArgumentException>(() => coordinator.SetGlobalShortcutAsync(
            GlobalShortcutAction.ToggleOverlay,
            s_compose));
        await Assert.ThrowsAsync<ArgumentException>(() => coordinator.SetGlobalShortcutAsync(
            GlobalShortcutAction.ToggleOverlay,
            new GlobalShortcut(GlobalShortcutModifiers.Control | GlobalShortcutModifiers.Alt, 0x4F)));

        Assert.Equal(registrations, registrar.Calls.Count);
        Assert.Equal(0, preferences.SaveCount);
    }

    private sealed class FakeRegistrar : IGlobalShortcutRegistrar
    {
        public Dictionary<GlobalShortcut, GlobalShortcutRegistrationStatus> Results { get; } = [];

        public List<(GlobalShortcutAction Action, GlobalShortcut? Shortcut)> Calls { get; } = [];

        public GlobalShortcutRegistrationStatus Register(GlobalShortcutAction action, GlobalShortcut? shortcut)
        {
            Calls.Add((action, shortcut));
            return shortcut is { } value
                ? Results.GetValueOrDefault(value, GlobalShortcutRegistrationStatus.Registered)
                : GlobalShortcutRegistrationStatus.NotSet;
        }
    }

    private sealed class MemoryPreferences(AppPreferences saved) : IPreferencesStore
    {
        public AppPreferences Saved { get; private set; } = saved;

        public int SaveCount { get; private set; }

        public bool FailSaves { get; set; }

        public ValueTask<AppPreferences> LoadAsync(CancellationToken cancellationToken = default) =>
            ValueTask.FromResult(Saved);

        public ValueTask SaveAsync(AppPreferences preferences, CancellationToken cancellationToken = default)
        {
            if (FailSaves)
            {
                throw new IOException("The test store rejects writes.");
            }

            Saved = preferences;
            SaveCount++;
            return ValueTask.CompletedTask;
        }
    }
}
