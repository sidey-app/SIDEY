using Microsoft.UI.Xaml;

namespace Sidey.App;

public sealed partial class UnsupportedWindowsWindow : Window
{
    public UnsupportedWindowsWindow()
    {
        InitializeComponent();
        Title = "SIDEY — 지원되지 않는 Windows";
    }
}
