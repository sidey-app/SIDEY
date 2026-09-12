using Microsoft.UI.Xaml;

using Sidey.Core.Localization;

namespace Sidey.App.Views;

public sealed partial class UnsupportedWindowsWindow : Window
{
    public UnsupportedWindowsWindow()
    {
        InitializeComponent();
        Title = I18n.Get("unsupported.windowTitle");
        SideyWindowIcon.Apply(AppWindow);
    }
}
