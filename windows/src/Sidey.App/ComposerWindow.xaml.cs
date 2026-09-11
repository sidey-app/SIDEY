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

    private readonly Microsoft.UI.Dispatching.DispatcherQueue _uiDispatcherQueue;
    private readonly WindowsBorderlessWindowController _borderlessWindow;
    private bool _focusRequested;
    private bool _isHiding;
    private bool _isVisible;
    private bool _isClosed;
    private bool _allowClose;
    private int _focusRequestId;

    public ComposerWindow(ComposerViewModel viewModel)
    {
        ViewModel = viewModel ?? throw new ArgumentNullException(nameof(viewModel));
        _uiDispatcherQueue = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread();
        InitializeComponent();
        ComposerRoot.DataContext = ViewModel;
        Title = I18n.Get("window.composerTitle");
        SideyWindowIcon.Apply(AppWindow);
        AppWindow.IsShownInSwitchers = false;
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsAlwaysOnTop = true;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
            presenter.IsResizable = false;
        }

        _borderlessWindow = new WindowsBorderlessWindowController(
            WinRT.Interop.WindowNative.GetWindowHandle(this));

        ViewModel.CloseRequested += OnCloseRequested;
        MessageInput.Loaded += OnMessageInputLoaded;
        Activated += OnWindowActivated;
        AppWindow.Closing += OnAppWindowClosing;
        Closed += OnWindowClosed;
    }

    public ComposerViewModel ViewModel { get; }

    public void ShowAndFocus(string? monitorIdentifier)
    {
        if (_isClosed)
        {
            return;
        }

        ViewModel.OnShown();
        ResizeAndCenter(monitorIdentifier);
        _isVisible = true;
        AppWindow.Show();
        Activate();
        SideyWindowActivation.BringToForeground(this);
        RequestMessageInputFocus();
    }

    public void HideComposer()
    {
        if (_isClosed || !_isVisible || _isHiding)
        {
            return;
        }

        _isHiding = true;
        _isVisible = false;
        try
        {
            _focusRequestId++;
            _focusRequested = false;
            ViewModel.OnHidden();
            StartupDiagnostics.Stage("composer-hide-started");
            AppWindow.Hide();
            StartupDiagnostics.Stage("composer-hidden");
        }
        finally
        {
            _isHiding = false;
        }
    }

    public void RestoreDraftAndFocus(string body)
    {
        if (_isClosed)
        {
            return;
        }

        ViewModel.RestoreDraft(body);
        _isVisible = true;
        AppWindow.Show();
        Activate();
        SideyWindowActivation.BringToForeground(this);
        RequestMessageInputFocus();
    }

    public void CloseForExit()
    {
        if (_isClosed)
        {
            return;
        }

        _allowClose = true;
        Close();
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
            if (!_focusRequested && _isVisible && !_isHiding)
            {
                HideComposer();
            }

            return;
        }

        if (_isVisible)
        {
            RequestMessageInputFocus();
        }
    }

    private void OnMessageInputLoaded(object sender, RoutedEventArgs args)
    {
        if (!_isClosed && _isVisible)
        {
            RequestMessageInputFocus();
        }
    }

    private void OnCloseRequested()
    {
        if (_isClosed)
        {
            return;
        }

        if (!_uiDispatcherQueue.TryEnqueue(() =>
            {
                if (!_isClosed)
                {
                    HideComposer();
                }
            }))
        {
            StartupDiagnostics.Stage("composer-hide-queue-rejected");
        }
    }

    private void OnAppWindowClosing(
        AppWindow sender,
        AppWindowClosingEventArgs args)
    {
        _ = sender;
        if (_allowClose)
        {
            return;
        }

        args.Cancel = true;
        OnCloseRequested();
    }

    private void OnWindowClosed(object sender, WindowEventArgs args)
    {
        _ = sender;
        _ = args;
        _isClosed = true;
        _borderlessWindow.Dispose();
        _focusRequestId++;
        _focusRequested = false;
        _isVisible = false;
        AppWindow.Closing -= OnAppWindowClosing;
        MessageInput.Loaded -= OnMessageInputLoaded;
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
            if (_isClosed || requestId != _focusRequestId || !_isVisible)
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
        Windows.Graphics.SizeInt32 windowSize = AppWindow.Size;
        AppWindow.Move(new Windows.Graphics.PointInt32(
            workArea.X + ((workArea.Width - windowSize.Width) / 2),
            workArea.Y + (int)Math.Round(10 * scale)));
    }
}
