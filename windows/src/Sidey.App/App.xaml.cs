using Microsoft.UI.Xaml;
using Sidey.Core.Domain;
using Sidey.Overlay;
using Sidey.Platform.Windows;

namespace Sidey.App;

public partial class App : Application
{
    private Window? _window;
    private LocalHamsterSliceSession? _slice;
    private ComposerWindow? _composer;
    private OverlayRegionPreference _preference = OverlayRegionPreference.Default;

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
        mainWindow.PresetRequested += OnPresetRequested;
        mainWindow.Activate();
        StartSlice(mainWindow);
    }

    private void StartSlice(MainWindow mainWindow)
    {
        try
        {
            _slice?.Dispose();
            _slice = LocalHamsterSliceSession.Start(
                _preference,
                RequestComposer,
                ReportRenderingFailure);
            mainWindow.SetSliceReady(_preference);
        }
        catch (Exception exception)
        {
            mainWindow.SetSliceFailure(exception);
        }
    }

    private void OnPresetRequested(OverlayRegionPreference preference)
    {
        _preference = preference;
        if (_window is MainWindow mainWindow)
        {
            StartSlice(mainWindow);
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

    private void ReportRenderingFailure(Exception exception)
    {
        if (_window is MainWindow mainWindow)
        {
            mainWindow.DispatcherQueue.TryEnqueue(() => mainWindow.SetSliceFailure(exception));
        }
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
        if (_window is MainWindow mainWindow)
        {
            mainWindow.PresetRequested -= OnPresetRequested;
        }

        try
        {
            _slice?.Dispose();
        }
        catch (Exception exception)
        {
            System.Diagnostics.Trace.TraceError("SIDEY overlay shutdown failed: {0}", exception);
        }

        _slice = null;
        if (_composer is not null)
        {
            _composer.SendRequested -= OnLocalSendRequested;
            _composer.Close();
            _composer = null;
        }
    }
}
