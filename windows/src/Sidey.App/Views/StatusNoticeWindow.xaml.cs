using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;
using Sidey.Core.Domain;
using Sidey.Core.Localization;

namespace Sidey.App.Views;

// Briefly confirms a change made with a global shortcut. The user pressed the shortcut
// in another application, so the notice never takes activation or keyboard focus.
public sealed partial class StatusNoticeWindow : Window
{
    private const int NoticeWidth = 400;
    private const int NoticeHeight = 72;
    private const int StackGap = 8;
    private const int DisplayMilliseconds = 1600;

    private readonly WindowsBorderlessWindowController _borderlessWindow;
    private readonly DispatcherQueueTimer _hideTimer;
    private bool _isClosed;
    private bool _allowClose;

    public StatusNoticeWindow()
    {
        InitializeComponent();
        Title = I18n.Get("window.statusNoticeTitle");
        AppWindow.IsShownInSwitchers = false;
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsAlwaysOnTop = true;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
            presenter.IsResizable = false;
        }

        nint handle = WinRT.Interop.WindowNative.GetWindowHandle(this);
        _borderlessWindow = new WindowsBorderlessWindowController(handle);
        SideyWindowActivation.PreventActivation(handle);
        _hideTimer = DispatcherQueue.CreateTimer();
        _hideTimer.Interval = TimeSpan.FromMilliseconds(DisplayMilliseconds);
        _hideTimer.IsRepeating = false;
        _hideTimer.Tick += OnHideTimerTick;
        AppWindow.Closing += OnAppWindowClosing;
        Closed += OnWindowClosed;
    }

    public void ApplyTheme(AppThemePreference theme)
    {
        if (!_isClosed)
        {
            SideyWindowTheme.Apply(NoticeRoot, theme);
        }
    }

    public void ShowNotice(string title, string detail, string? monitorIdentifier, bool belowComposer)
    {
        if (_isClosed)
        {
            return;
        }

        _hideTimer.Stop();
        Title = I18n.Get("window.statusNoticeTitle");
        TitleText.Text = title;
        DetailText.Text = detail;
        ResizeAndPlace(monitorIdentifier, belowComposer);
        AppWindow.Show(activateWindow: false);
        _hideTimer.Start();
        if (AutomationPeer.ListenerExists(AutomationEvents.LiveRegionChanged))
        {
            FrameworkElementAutomationPeer.CreatePeerForElement(TitleText)
                .RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
        }
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

    private void HideNotice()
    {
        _hideTimer.Stop();
        if (!_isClosed)
        {
            AppWindow.Hide();
        }
    }

    private void OnHideTimerTick(DispatcherQueueTimer sender, object args)
    {
        _ = sender;
        _ = args;
        HideNotice();
    }

    private void OnAppWindowClosing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        _ = sender;
        if (_allowClose)
        {
            return;
        }

        args.Cancel = true;
        HideNotice();
    }

    private void OnWindowClosed(object sender, WindowEventArgs args)
    {
        _ = sender;
        _ = args;
        _isClosed = true;
        _hideTimer.Stop();
        _hideTimer.Tick -= OnHideTimerTick;
        AppWindow.Closing -= OnAppWindowClosing;
        _borderlessWindow.Dispose();
    }

    private void ResizeAndPlace(string? monitorIdentifier, bool belowComposer)
    {
        WindowsMonitorInfo monitor = WindowsMonitorService.Select(monitorIdentifier);
        double scale = monitor.Dpi / 96d;
        int width = (int)Math.Round(NoticeWidth * scale, MidpointRounding.AwayFromZero);
        int height = (int)Math.Round(NoticeHeight * scale, MidpointRounding.AwayFromZero);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(width, height));

        // The composer uses the same top-center spot, so stack below it while it is open.
        int top = ComposerWindow.TopMargin
            + (belowComposer ? ComposerWindow.ComposerHeight + StackGap : 0);
        NativePixelRect workArea = monitor.WorkAreaPixels;
        Windows.Graphics.SizeInt32 windowSize = AppWindow.Size;
        AppWindow.Move(new Windows.Graphics.PointInt32(
            workArea.X + ((workArea.Width - windowSize.Width) / 2),
            workArea.Y + (int)Math.Round(top * scale)));
    }
}
