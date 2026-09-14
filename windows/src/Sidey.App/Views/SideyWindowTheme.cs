using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Sidey.Core.Domain;

namespace Sidey.App.Views;

internal static class SideyWindowTheme
{
    public static void FollowTitleBarTheme(Window window, FrameworkElement root)
    {
        // The native caption defaults to Legacy; RequestedTheme only updates XAML.
        // Leave caption colors to Windows so hover/inactive/high-contrast states
        // keep their native behavior.
        bool closed = false;
        void UpdateTheme(FrameworkElement sender, object args)
        {
            // Synchronize the native caption after XAML has finished propagating
            // the actual theme through the visual tree.
            root.DispatcherQueue.TryEnqueue(() =>
            {
                if (!closed)
                {
                    window.AppWindow.TitleBar.PreferredTheme = root.ActualTheme == ElementTheme.Dark
                        ? TitleBarTheme.Dark
                        : TitleBarTheme.Light;
                }
            });
        }

        void OnLoaded(object sender, RoutedEventArgs args) => UpdateTheme(root, args);

        void OnClosed(object sender, WindowEventArgs args)
        {
            closed = true;
            root.ActualThemeChanged -= UpdateTheme;
            root.Loaded -= OnLoaded;
            window.Closed -= OnClosed;
        }

        root.ActualThemeChanged += UpdateTheme;
        root.Loaded += OnLoaded;
        window.Closed += OnClosed;
        UpdateTheme(root, EventArgs.Empty);
    }

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
