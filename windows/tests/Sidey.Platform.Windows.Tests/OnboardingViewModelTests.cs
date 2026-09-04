using Sidey.Core.Domain;
using Sidey.Presentation.Services;
using Sidey.Presentation.ViewModels;

namespace Sidey.Platform.Windows.Tests;

public sealed class OnboardingViewModelTests
{
    [Fact]
    public void CharacterPickerKeepsTheFiveFreeWindowsSelections()
    {
        var viewModel = new OnboardingViewModel(new FakeSideyCoordinator());

        Assert.Equal(
            ["pixel_hamster", "pixel_cat", "pixel_puppy", "pixel_rabbit", "pixel_penguin"],
            viewModel.CharacterSelections.Select(character => character.Id));
    }

    [Fact]
    public void IssuedCharactersAppearInTheOnboardingProfilePicker()
    {
        var coordinator = new FakeSideyCoordinator
        {
            State = CoordinatorState.Initial with
            {
                ActiveEntitlementKeys = new HashSet<string>(StringComparer.Ordinal)
                {
                    "character:pixel_starlight_upalupa",
                },
            },
        };

        var viewModel = new OnboardingViewModel(coordinator);

        Assert.Contains(
            viewModel.CharacterSelections,
            character => character.Id == "pixel_starlight_upalupa");
    }

    [Fact]
    public async Task PreviewModeWalksEveryStepWithoutServerMutations()
    {
        var coordinator = new FakeSideyCoordinator
        {
            State = CoordinatorState.Initial with
            {
                Preferences = AppPreferences.Default with { OnboardingCompleted = true },
                Connected = false,
            },
        };
        var viewModel = new OnboardingViewModel(coordinator, isPreviewMode: true)
        {
            Nickname = "미리보기",
            RoomName = "미리보기 그룹",
        };

        viewModel.BeginCommand.Execute(null);
        Assert.True(viewModel.IsProfileStep);
        Assert.True(viewModel.CanSaveProfile);

        await viewModel.SaveProfileCommand.ExecuteAsync(null);
        Assert.True(viewModel.IsGroupStep);

        await viewModel.CreateRoomCommand.ExecuteAsync(null);
        Assert.True(viewModel.IsReadyStep);
        Assert.Equal(0, coordinator.SaveProfileCallCount);
        Assert.Equal(0, coordinator.CreateRoomCallCount);
        Assert.Equal(0, coordinator.JoinRoomCallCount);
    }

    [Fact]
    public async Task PreviewModePrefillsExistingDataButDoesNotSkipSteps()
    {
        Guid userId = Guid.NewGuid();
        var profile = new Profile(userId, "기존 이름", "pixel_penguin");
        var room = new Room(
            Guid.NewGuid(),
            "기존 그룹",
            userId,
            [new RoomMember(userId, profile.Nickname, profile.CharacterId, PresenceState.Online)],
            "ABCD",
            true,
            1);
        var coordinator = new FakeSideyCoordinator
        {
            State = CoordinatorState.Initial with
            {
                Profile = profile,
                Rooms = [room],
                ActiveRoomId = room.Id,
                Preferences = AppPreferences.Default with { OnboardingCompleted = true },
                Connected = true,
            },
        };
        var viewModel = new OnboardingViewModel(coordinator, isPreviewMode: true);

        Assert.Equal("기존 이름", viewModel.Nickname);
        Assert.Equal("pixel_penguin", viewModel.SelectedCharacterId);
        Assert.Equal("기존 그룹", viewModel.RoomName);
        Assert.True(viewModel.IsLanding);

        viewModel.BeginCommand.Execute(null);
        Assert.True(viewModel.IsProfileStep);

        await viewModel.SaveProfileCommand.ExecuteAsync(null);
        Assert.True(viewModel.IsGroupStep);
        Assert.Equal("기존 그룹", viewModel.RoomName);

        await viewModel.CreateRoomCommand.ExecuteAsync(null);
        Assert.True(viewModel.IsReadyStep);
    }

    [Fact]
    public void NewInstallationStartsWithLandingThenMovesToProfile()
    {
        var viewModel = new OnboardingViewModel(new FakeSideyCoordinator());

        Assert.True(viewModel.IsLanding);

        viewModel.BeginCommand.Execute(null);

        Assert.True(viewModel.IsProfileStep);
        Assert.True(viewModel.IsSetupVisible);
    }

    [Fact]
    public void RestoredProfileContinuesAtGroupStep()
    {
        var coordinator = new FakeSideyCoordinator
        {
            State = CoordinatorState.Initial with
            {
                Profile = new Profile(Guid.NewGuid(), "사이드", "pixel_cat"),
                Connected = true,
            },
        };
        var viewModel = new OnboardingViewModel(coordinator);

        viewModel.BeginCommand.Execute(null);

        Assert.True(viewModel.IsGroupStep);
        Assert.Equal("사이드", viewModel.Nickname);
        Assert.Equal("pixel_cat", viewModel.SelectedCharacterId);
    }

    [Fact]
    public void ProfileAndRoomCompletionMovesToReadyStep()
    {
        Guid userId = Guid.NewGuid();
        var profile = new Profile(userId, "사이드", "pixel_hamster");
        var room = new Room(
            Guid.NewGuid(),
            "친구들",
            userId,
            [new RoomMember(userId, profile.Nickname, profile.CharacterId, PresenceState.Online)],
            "ABCD",
            true,
            1);
        var coordinator = new FakeSideyCoordinator
        {
            State = CoordinatorState.Initial with
            {
                Profile = profile,
                Connected = true,
            },
        };
        var viewModel = new OnboardingViewModel(coordinator);
        viewModel.BeginCommand.Execute(null);

        viewModel.ApplyState(coordinator.State with
        {
            Rooms = [room],
            ActiveRoomId = room.Id,
            Preferences = coordinator.State.Preferences with { OnboardingCompleted = true },
        });

        Assert.True(viewModel.IsReadyStep);
        Assert.False(viewModel.CanGoBack);
    }

    [Fact]
    public void ProfileActionRequiresConnectionAndValidNickname()
    {
        var coordinator = new FakeSideyCoordinator();
        var viewModel = new OnboardingViewModel(coordinator)
        {
            Nickname = "사이드",
        };

        Assert.False(viewModel.CanSaveProfile);

        viewModel.ApplyState(coordinator.State with { Connected = true });

        Assert.True(viewModel.CanSaveProfile);
    }

    [Fact]
    public void StateUpdatePreservesUnsavedProfileDraft()
    {
        var profile = new Profile(Guid.NewGuid(), "saved-name", "pixel_hamster");
        var coordinator = new FakeSideyCoordinator
        {
            State = CoordinatorState.Initial with
            {
                Profile = profile,
                Connected = true,
            },
        };
        var viewModel = new OnboardingViewModel(coordinator)
        {
            Nickname = "draft-name",
            SelectedCharacterId = "pixel_cat",
        };

        viewModel.ApplyState(coordinator.State with { Connected = false });

        Assert.Equal("draft-name", viewModel.Nickname);
        Assert.Equal("pixel_cat", viewModel.SelectedCharacterId);
    }
}
