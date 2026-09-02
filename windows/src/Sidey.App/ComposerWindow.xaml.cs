using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Sidey.Core.Localization;
using Sidey.Platform.Windows;
using Sidey.Presentation.ViewModels;
using Windows.System;

namespace Sidey.App;

public sealed partial class ComposerWindow : Window
{
    private const int ComposerWidth = 400;
    private const int ComposerHeight = 56;
    private const int FocusAttemptCount = 3;

    private bool _focusRequested;
    private int _focusRequestId;

    public ComposerWindow(ComposerViewModel viewModel)
    {
        ViewModel = viewModel ?? throw new ArgumentNullException(nameof(viewModel));
        InitializeComponent();
        ComposerRoot.DataContext = ViewModel;
        Title = I18n.Get("window.composerTitle");
        SideyWindowIcon.Apply(AppWindow);
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

        ViewModel.CloseRequested += OnCloseRequested;
        Activated += OnWindowActivated;
        Closed += OnWindowClosed;
    }

    public ComposerViewModel ViewModel { get; }

    public void ShowAndFocus(string? monitorIdentifier)
    {
        ViewModel.OnShown();
        ResizeAndCenter(monitorIdentifier);
        AppWindow.Show();
        Activate();
        RequestMessageInputFocus();
    }

    public void HideComposer()
    {
        _focusRequestId++;
        _focusRequested = false;
        ViewModel.OnHidden();
        AppWindow.Hide();
    }

    public void RestoreDraftAndFocus(string body)
    {
        ViewModel.RestoreDraft(body);
        AppWindow.Show();
        Activate();
        RequestMessageInputFocus();
    }

    private void OnMessageInputPreviewKeyDown(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        if (args.Key == VirtualKey.Escape)
        {
            args.Handled = true;
            ViewModel.CloseCommand.Execute(null);
            return;
        }

        if (args.Key != VirtualKey.Enter)
        {
            return;
        }

        Windows.UI.Core.CoreVirtualKeyStates shiftState = InputKeyboardSource.GetKeyStateForCurrentThread(
            VirtualKey.Shift);
        if ((shiftState & Windows.UI.Core.CoreVirtualKeyStates.Down) != 0)
        {
            if (!ViewModel.CanAddLine)
            {
                args.Handled = true;
            }

            return;
        }

        args.Handled = true;
        if (ViewModel.SendCommand.CanExecute(null))
        {
            ViewModel.SendCommand.Execute(null);
            RequestMessageInputFocus();
        }
    }

    private void OnWindowActivated(object sender, WindowActivatedEventArgs args)
    {
        _ = sender;
        if (args.WindowActivationState == WindowActivationState.Deactivated)
        {
            if (!_focusRequested && AppWindow.IsVisible)
            {
                HideComposer();
            }

            return;
        }

        if (AppWindow.IsVisible)
        {
            RequestMessageInputFocus();
        }
    }

    private void OnCloseRequested() => DispatcherQueue.TryEnqueue(HideComposer);

    private void OnWindowClosed(object sender, WindowEventArgs args)
    {
        _ = sender;
        _ = args;
        ViewModel.CloseRequested -= OnCloseRequested;
        ViewModel.Dispose();
    }

    private void RequestMessageInputFocus()
    {
        _focusRequested = true;
        int requestId = ++_focusRequestId;
        QueueMessageInputFocus(requestId, FocusAttemptCount);
    }

    private void QueueMessageInputFocus(int requestId, int attemptsRemaining)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (requestId != _focusRequestId || !AppWindow.IsVisible)
            {
                return;
            }

            if (MessageInput.Focus(FocusState.Programmatic))
            {
                MessageInput.SelectionStart = MessageInput.Text.Length;
                _focusRequested = false;
                return;
            }

            if (attemptsRemaining > 0)
            {
                QueueMessageInputFocus(requestId, attemptsRemaining - 1);
            }
            else
            {
                _focusRequested = false;
            }
        });
    }

    private void ResizeAndCenter(string? monitorIdentifier)
    {
        WindowsMonitorInfo monitor = WindowsMonitorService.Select(monitorIdentifier);
        double scale = monitor.Dpi / 96d;
        int width = (int)Math.Round(ComposerWidth * scale, MidpointRounding.AwayFromZero);
        int height = (int)Math.Round(ComposerHeight * scale, MidpointRounding.AwayFromZero);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(width, height));

        NativePixelRect workArea = monitor.WorkAreaPixels;
        AppWindow.Move(new Windows.Graphics.PointInt32(
            workArea.X + ((workArea.Width - width) / 2),
            workArea.Y + (int)Math.Round(10 * scale)));
    }
}
