using Sidey.Presentation.ViewModels;

namespace Sidey.Platform.Windows.Tests;

public sealed class ComposerViewModelTests
{
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
}
