using Microsoft.UI.Xaml;
using Sidey.Overlay;
using Sidey.Platform.Windows;

namespace Sidey.App;

public partial class App : Application
{
    private Window? _window;
    private LocalHamsterSliceSession? _slice;
    private ComposerWindow? _composer;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        if (!WindowsVersionGuard.IsSupported())
        {
            _window = new UnsupportedWindowsWindow();
            _window.Activate();
            return;
        }

        var mainWindow = new MainWindow();
        _window = mainWindow;
        mainWindow.Closed += OnMainWindowClosed;
        mainWindow.Activate();
        try
        {
            _slice = LocalHamsterSliceSession.Start(RequestComposer);
            mainWindow.SetSliceReady();
        }
        catch (Exception exception)
        {
            mainWindow.SetSliceFailure(exception);
        }
    }

    private void RequestComposer()
    {
        if (_window is MainWindow mainWindow)
        {
            mainWindow.DispatcherQueue.TryEnqueue(ShowComposer);
        }
    }

    private void ShowComposer()
    {
        if (_composer is null)
        {
            _composer = new ComposerWindow();
            _composer.SendRequested += OnLocalSendRequested;
        }

        _composer.ShowAndFocus();
    }

    private void OnLocalSendRequested(string body)
    {
        _ = body;
        if (_window is MainWindow mainWindow)
        {
            mainWindow.SetMessageInputVerified();
        }
    }

    private void OnMainWindowClosed(object sender, WindowEventArgs args)
    {
        _slice?.Dispose();
        _slice = null;
        if (_composer is not null)
        {
            _composer.SendRequested -= OnLocalSendRequested;
            _composer.Close();
            _composer = null;
        }
    }
}
