using Microsoft.UI.Xaml;
using Sidey.Core.Domain;

namespace Sidey.App.Views;

internal static class SideyWindowTheme
{
    public static void Apply(FrameworkElement root, AppThemePreference theme)
    {
        ArgumentNullException.ThrowIfNull(root);
        root.RequestedTheme = theme switch
        {
            AppThemePreference.Light => ElementTheme.Light,
            AppThemePreference.Dark => ElementTheme.Dark,
            _ => ElementTheme.Default,
        };
    }
}
