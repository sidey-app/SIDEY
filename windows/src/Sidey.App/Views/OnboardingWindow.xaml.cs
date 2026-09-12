using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Sidey.Core.Localization;
using Sidey.Platform.Windows;
using Sidey.Presentation.Services;
using Sidey.Presentation.ViewModels;

namespace Sidey.App.Views;

public sealed partial class OnboardingWindow : Window
{
    private bool _isClosed;

    public OnboardingWindow(AppCoordinator coordinator)
    {
        InitializeComponent();
        ViewModel = new OnboardingViewModel(coordinator);
        OnboardingRoot.DataContext = ViewModel;
        ViewModel.Completed += OnCompleted;
        Closed += OnWindowClosed;
        Title = I18n.Get("window.settingsTitle");
        LandingIcon.Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(Path.Combine(
            SideyDeploymentPaths.DeploymentRoot(),
            "Assets",
            "Icons",
            "SideyAppIcon.png")));
        SideyWindowIcon.Apply(AppWindow);
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(DragRegion);
        ApplyBackdrop();
        ApplyResponsiveSize();
        AppWindow.Closing += OnAppWindowClosing;
    }

    public event Action? Completed;

    public OnboardingViewModel ViewModel { get; }

    public void ApplyState(CoordinatorState state)
    {
        if (!_isClosed)
        {
            ViewModel.ApplyState(state);
        }
    }

    public void ShowError(Exception exception)
    {
        if (!_isClosed)
        {
            ViewModel.ReportError(exception);
        }
    }

    public void ShowAndActivate()
    {
        if (_isClosed)
        {
            return;
        }

        AppWindow.Show();
        Activate();
        SideyWindowActivation.BringToForeground(this);
    }

    private void OnCompleted() => Completed?.Invoke();

    private void OnAppWindowClosing(
        Microsoft.UI.Windowing.AppWindow sender,
        Microsoft.UI.Windowing.AppWindowClosingEventArgs args)
    {
        _ = sender;
        _ = args;
        PrepareForClose();
    }

    private void PrepareForClose()
    {
        if (_isClosed)
        {
            return;
        }

        _isClosed = true;
        OnboardingRoot.DataContext = null;
        ViewModel.Dispose();
    }

    private void ApplyBackdrop()
    {
        if (OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000)
            && MicaController.IsSupported())
        {
            SystemBackdrop = new MicaBackdrop { Kind = MicaKind.Base };
        }
    }

    private void ApplyResponsiveSize()
    {
        WindowsMonitorInfo monitor = WindowsMonitorService.Select(identifier: null);
        ResponsiveWindowSize size = ResponsiveWindowSizePolicy.Calculate(
            monitor,
            SideyWindowKind.Onboarding);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(size.Width, size.Height));
        AppWindow.Move(new Windows.Graphics.PointInt32(
            monitor.WorkAreaPixels.X + ((monitor.WorkAreaPixels.Width - size.Width) / 2),
            monitor.WorkAreaPixels.Y + ((monitor.WorkAreaPixels.Height - size.Height) / 2)));
    }

    private void OnWindowClosed(object sender, WindowEventArgs args)
    {
        _ = sender;
        _ = args;
        PrepareForClose();
        AppWindow.Closing -= OnAppWindowClosing;
        ViewModel.Completed -= OnCompleted;
    }
}
