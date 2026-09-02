using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Sidey.Core.Localization;
using Sidey.Platform.Windows;
using Sidey.Presentation.Services;
using Sidey.Presentation.ViewModels;

namespace Sidey.App;

public sealed partial class HistoryWindow : Window
{
    private readonly CoordinatorState _initialState;

    public HistoryWindow(HistoryWindowViewModel viewModel)
    {
        ViewModel = viewModel ?? throw new ArgumentNullException(nameof(viewModel));
        _initialState = viewModel.CurrentState;
        InitializeComponent();
        HistoryRoot.DataContext = ViewModel;
        Title = I18n.Get("window.historyTitle");
        SideyWindowIcon.Apply(AppWindow);
        ApplyResponsiveSize();
        ApplyBackdrop();
        Closed += OnWindowClosed;
    }

    public HistoryWindowViewModel ViewModel { get; }

    public void ApplyState(CoordinatorState state) => ViewModel.ApplyState(state);

    public void ShowAndActivate()
    {
        AppWindow.Show();
        Activate();
        SideyWindowActivation.BringToForeground(this);
        _ = ViewModel.ActivateAsync();
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
        WindowsMonitorInfo monitor = WindowsMonitorService.Select(
            _initialState.Preferences.OverlayRegion.MonitorIdentifier);
        ResponsiveWindowSize size = ResponsiveWindowSizePolicy.Calculate(
            monitor,
            SideyWindowKind.History);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(size.Width, size.Height));
        AppWindow.Move(new Windows.Graphics.PointInt32(
            monitor.WorkAreaPixels.X + ((monitor.WorkAreaPixels.Width - size.Width) / 2),
            monitor.WorkAreaPixels.Y + ((monitor.WorkAreaPixels.Height - size.Height) / 2)));
    }

    private void OnHistoryContainerContentChanging(
        ListViewBase sender,
        ContainerContentChangingEventArgs args)
    {
        _ = sender;
        if (args.ItemIndex >= ViewModel.Items.Count - 5
            && ViewModel.LoadMoreCommand.CanExecute(null))
        {
            ViewModel.LoadMoreCommand.Execute(null);
        }
    }

    private void OnWindowClosed(object sender, WindowEventArgs args)
    {
        _ = sender;
        _ = args;
        ViewModel.Dispose();
    }
}
