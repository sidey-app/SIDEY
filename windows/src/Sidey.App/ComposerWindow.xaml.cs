using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Sidey.Core.Domain;
using Windows.System;
using Windows.UI.Core;

namespace Sidey.App;

public sealed partial class ComposerWindow : Window
{
    private const int ComposerWidth = 400;
    private const int ComposerHeight = 56;

    private CancellationTokenSource? _autoClose;

    public ComposerWindow()
    {
        InitializeComponent();
        Title = "SIDEY 메시지";
        ExtendsContentIntoTitleBar = true;
        AppWindow.IsShownInSwitchers = false;
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsAlwaysOnTop = true;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
            presenter.IsResizable = false;
            presenter.SetBorderAndTitleBar(false, false);
        }
        Activated += OnWindowActivated;
    }

    public event Action<string>? SendRequested;
    public event Action<bool>? TypingChanged;

    public void ShowAndFocus(string? monitorIdentifier)
    {
        Activate();
        ResizeAndCenter(monitorIdentifier);
        MessageInput.Focus(FocusState.Programmatic);
    }

    public void HideComposer()
    {
        CancelAutoClose();
        TypingChanged?.Invoke(false);
        AppWindow.Hide();
    }

    public void RestoreDraftAndFocus(string body)
    {
        CancelAutoClose();
        MessageInput.Text = body;
        Activate();
        MessageInput.Focus(FocusState.Programmatic);
        MessageInput.SelectionStart = MessageInput.Text.Length;
    }

    private void OnMessageInputKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == VirtualKey.Escape)
        {
            args.Handled = true;
            HideComposer();
            return;
        }

        if (args.Key != VirtualKey.Enter)
        {
            return;
        }

        var shiftState = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift);
        if ((shiftState & CoreVirtualKeyStates.Down) != 0)
        {
            if (MessageInput.Text.Count(character => character == '\n') + 1
                >= MessageValidator.MaximumLines)
            {
                args.Handled = true;
            }

            return;
        }

        args.Handled = true;
        var body = MessageValidator.Normalize(MessageInput.Text);
        if (!MessageValidator.IsValid(body))
        {
            MessageInput.PlaceholderText = "1~200자, 최대 3줄까지만 보낼 수 있음";
            return;
        }

        SendRequested?.Invoke(body);
        MessageInput.Text = string.Empty;
        TypingChanged?.Invoke(false);
        ScheduleAutoClose();
    }

    private void OnMessageInputTextChanged(object sender, TextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        TypingChanged?.Invoke(!string.IsNullOrWhiteSpace(MessageInput.Text));
    }

    private void OnWindowActivated(object sender, WindowActivatedEventArgs args)
    {
        _ = sender;
        if (args.WindowActivationState == WindowActivationState.Deactivated
            && AppWindow.IsVisible)
        {
            HideComposer();
        }
    }

    private void ScheduleAutoClose()
    {
        CancelAutoClose();
        _autoClose = new CancellationTokenSource();
        _ = CloseAfterDelayAsync(_autoClose.Token);
    }

    private async Task CloseAfterDelayAsync(CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(5), cancellationToken);
            DispatcherQueue.TryEnqueue(HideComposer);
        }
        catch (OperationCanceledException)
        {
        }
    }

    private void CancelAutoClose()
    {
        _autoClose?.Cancel();
        _autoClose?.Dispose();
        _autoClose = null;
    }

    private void ResizeAndCenter(string? monitorIdentifier)
    {
        var monitor = WindowsMonitorService.Select(monitorIdentifier);
        var scale = monitor.Dpi / 96d;
        var width = (int)Math.Round(ComposerWidth * scale, MidpointRounding.AwayFromZero);
        var height = (int)Math.Round(ComposerHeight * scale, MidpointRounding.AwayFromZero);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(width, height));

        var workArea = monitor.WorkAreaPixels;
        AppWindow.Move(new Windows.Graphics.PointInt32(
            workArea.X + ((workArea.Width - width) / 2),
            workArea.Y + (int)Math.Round(10 * scale)));
    }
}
