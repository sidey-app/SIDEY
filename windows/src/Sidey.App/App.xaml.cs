using Microsoft.UI.Xaml;
using Sidey.Platform.Windows;

namespace Sidey.App;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = WindowsVersionGuard.IsSupported()
            ? new MainWindow()
            : new UnsupportedWindowsWindow();
        _window.Activate();
    }
}
