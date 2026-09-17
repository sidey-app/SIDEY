using Sidey.Core.Domain;
using Sidey.Presentation.Services;
using Sidey.Presentation.ViewModels;

namespace Sidey.Presentation.Tests;

public sealed class ComposerViewModelTests
{
    [Fact]
    public void ComposerCanHideAndReuseAfterSending()
    {
        using var viewModel = new ComposerViewModel();
        viewModel.Draft = "자동 닫기 테스트";
        viewModel.SendCommand.Execute(null);

        viewModel.OnHidden();
        viewModel.OnShown();
        viewModel.Draft = "다음 메시지";

        Assert.True(viewModel.SendCommand.CanExecute(null));
    }

    [Fact]
    public void DraftNotifiesTypingAndControlsSendAvailability()
    {
        using var viewModel = new ComposerViewModel();
        var typingStates = new List<bool>();
        viewModel.TypingChanged += typingStates.Add;

        Assert.False(viewModel.SendCommand.CanExecute(null));

        viewModel.Draft = "  안녕하세요  ";

        Assert.True(viewModel.SendCommand.CanExecute(null));
        Assert.Equal([true], typingStates);
    }

    [Fact]
    public void SendNormalizesBodyClearsDraftAndSchedulesDismissal()
    {
        using var viewModel = new ComposerViewModel();
        string? sentBody = null;
        viewModel.SendRequested += body => sentBody = body;
        viewModel.Draft = "  안녕하세요  ";

        viewModel.SendCommand.Execute(null);

        Assert.Equal("안녕하세요", sentBody);
        Assert.Equal(string.Empty, viewModel.Draft);
        Assert.False(viewModel.SendCommand.CanExecute(null));
    }

    [Fact]
    public void CloseCommandRequestsViewDismissal()
    {
        using var viewModel = new ComposerViewModel();
        bool closeRequested = false;
        viewModel.CloseRequested += () => closeRequested = true;

        viewModel.CloseCommand.Execute(null);

        Assert.True(closeRequested);
    }

    [Fact]
    public void InvalidDraftDoesNotReplaceCurrentDraft()
    {
        using var viewModel = new ComposerViewModel
        {
            Draft = "유효한 메시지",
        };
        string invalidDraft = string.Join('\n', Enumerable.Repeat("줄", 20));

        viewModel.Draft = invalidDraft;

        Assert.Equal("유효한 메시지", viewModel.Draft);
    }

    [Fact]
    public void ComposerWaitsForGroupsUntilTheFirstSnapshotArrives()
    {
        using var viewModel = new ComposerViewModel
        {
            Draft = "그룹을 기다리는 메시지",
        };
        bool sendRequested = false;
        viewModel.SendRequested += _ => sendRequested = true;

        viewModel.ApplyState(CoordinatorState.Initial);
        viewModel.SendCommand.Execute(null);

        Assert.Equal(ComposerAvailability.WaitingForGroups, viewModel.Availability);
        Assert.True(viewModel.IsWaitingForGroups);
        Assert.False(viewModel.IsGroupRequired);
        Assert.False(viewModel.CanCompose);
        Assert.False(viewModel.SendCommand.CanExecute(null));
        Assert.False(sendRequested);
        Assert.Equal("그룹을 기다리는 메시지", viewModel.Draft);
    }

    [Fact]
    public void ComposerAsksForAGroupWhenTheLoadedSnapshotHasNone()
    {
        using var viewModel = new ComposerViewModel();

        viewModel.ApplyState(LoadedState() with
        {
            Profile = new Profile(Guid.NewGuid(), "aryu", "pixel_hamster"),
        });

        Assert.Equal(ComposerAvailability.GroupRequired, viewModel.Availability);
        Assert.True(viewModel.IsGroupRequired);
        Assert.False(viewModel.IsWaitingForGroups);
        Assert.False(viewModel.CanCompose);
    }

    [Fact]
    public void ComposerSendsOnceAnActiveGroupAndProfileArrive()
    {
        using var viewModel = new ComposerViewModel();
        var changed = new List<string?>();
        viewModel.PropertyChanged += (_, args) => changed.Add(args.PropertyName);
        viewModel.ApplyState(CoordinatorState.Initial);
        viewModel.Draft = "안녕하세요";
        Assert.False(viewModel.SendCommand.CanExecute(null));

        viewModel.ApplyState(ActiveGroupState());

        Assert.Equal(ComposerAvailability.Ready, viewModel.Availability);
        Assert.True(viewModel.CanCompose);
        Assert.True(viewModel.SendCommand.CanExecute(null));
        Assert.Contains(nameof(ComposerViewModel.CanCompose), changed);
        Assert.Contains(nameof(ComposerViewModel.IsWaitingForGroups), changed);
    }

    [Fact]
    public void LosingTheActiveGroupStopsTypingAndKeepsTheDraft()
    {
        using var viewModel = new ComposerViewModel();
        viewModel.ApplyState(ActiveGroupState());
        viewModel.Draft = "보내기 전 메시지";
        var typingStates = new List<bool>();
        viewModel.TypingChanged += typingStates.Add;

        viewModel.ApplyState(LoadedState());

        Assert.Equal(ComposerAvailability.GroupRequired, viewModel.Availability);
        Assert.Equal([false], typingStates);
        Assert.Equal("보내기 전 메시지", viewModel.Draft);
    }

    [Fact]
    public void OpenGroupSettingsCommandRequestsGroupSetup()
    {
        using var viewModel = new ComposerViewModel();
        viewModel.ApplyState(LoadedState());
        bool requested = false;
        viewModel.GroupSettingsRequested += () => requested = true;

        viewModel.OpenGroupSettingsCommand.Execute(null);

        Assert.True(requested);
    }

    private static CoordinatorState LoadedState() => CoordinatorState.Initial with
    {
        ContentLoading = new RemoteContentLoadingState(
            RemoteDataLoadState.Ready,
            RemoteDataLoadState.Ready),
    };

    private static CoordinatorState ActiveGroupState()
    {
        var userId = Guid.NewGuid();
        var roomId = Guid.NewGuid();
        return LoadedState() with
        {
            Profile = new Profile(userId, "aryu", "pixel_hamster"),
            Rooms = [new Room(roomId, "친구들", userId, [], "••••-TEST", true, 1)],
            ActiveRoomId = roomId,
        };
    }
}
