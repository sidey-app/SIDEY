using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Sidey.App.Controls;
using Sidey.Platform.Windows;
using Windows.Foundation;
using Windows.Graphics;

namespace Sidey.App.Views;

public sealed partial class MainWindow
{
    internal async Task VerifyResponsiveWindowSmokeAsync()
    {
        SizeInt32 originalSize = AppWindow.Size;
        ElementTheme originalTheme = MainRoot.RequestedTheme;
        bool wasLoading = ViewModel.IsStoreLoading;
        try
        {
            // Exercise the Windows 10 path even when this smoke runs on Windows 11.
            SideyWindowTheme.ApplyBackdrop(this, MainFallbackBackground, allowMica: false);
            ViewModel.IsStoreLoading = false;
            Windows.UI.Color? darkBackgroundColor = null;
            foreach (ElementTheme theme in new[] { ElementTheme.Dark, ElementTheme.Light, ElementTheme.Default })
            {
                MainRoot.RequestedTheme = theme;
                await WaitForNextFrameAsync();
                await WaitForNextFrameAsync();
                TitleBarTheme expected = MainRoot.ActualTheme == ElementTheme.Dark ? TitleBarTheme.Dark : TitleBarTheme.Light;
                if (AppWindowTitleBar.IsCustomizationSupported() && AppWindow.TitleBar.PreferredTheme != expected)
                {
                    StartupDiagnostics.Stage($"caption-theme-smoke-failed requested={theme} actual={MainRoot.ActualTheme} caption={AppWindow.TitleBar.PreferredTheme}");
                    throw new InvalidOperationException("Caption theme did not follow the actual content theme.");
                }
                if (SystemBackdrop is not null || MainFallbackBackground.Visibility != Visibility.Visible
                    || MainFallbackBackground.Background is not SolidColorBrush background
                    || background.Color.A != 255 || background.Opacity != 1
                    || Math.Abs(MainFallbackBackground.ActualWidth - MainRoot.ActualWidth) > 1
                    || Math.Abs(MainFallbackBackground.ActualHeight - MainRoot.ActualHeight) > 1)
                {
                    StartupDiagnostics.Stage($"window-background-smoke-failed theme={theme} backdrop={SystemBackdrop?.GetType().Name} visible={MainFallbackBackground.Visibility} brush={MainFallbackBackground.Background} background={MainFallbackBackground.ActualWidth}x{MainFallbackBackground.ActualHeight} root={MainRoot.ActualWidth}x{MainRoot.ActualHeight}");
                    throw new InvalidOperationException("The non-Mica window background was not opaque and full size.");
                }
                if (theme == ElementTheme.Dark)
                    darkBackgroundColor = background.Color;
                if (theme == ElementTheme.Light && !new Windows.UI.ViewManagement.AccessibilitySettings().HighContrast
                    && darkBackgroundColor == background.Color)
                {
                    StartupDiagnostics.Stage($"window-background-theme-smoke-failed dark={darkBackgroundColor} light={background.Color}");
                    throw new InvalidOperationException("The non-Mica window background did not follow the theme.");
                }
            }
            foreach (string page in new[] { "profile", "store", "settings" })
            {
                ShowPage(page);
                foreach (int width in new[] { 1040, 720, 560, 1040 })
                {
                    if (page == "profile")
                    {
                        ShowPage("settings");
                    }
                    double scale = MainRoot.XamlRoot.RasterizationScale;
                    AppWindow.ResizeClient(new SizeInt32((int)Math.Round(width * scale), (int)Math.Round(700 * scale)));
                    await WaitForNextFrameAsync();
                    ShowPage(page);
                    await WaitForNextFrameAsync();
                    MainRoot.UpdateLayout();
                    if (page == "profile" && (HomePage.Opacity != 1
                        || FindVisualChild<Image>(CharacterSelector)?.Source is null))
                    {
                        throw new InvalidOperationException("Returning to the profile after resizing delayed its content.");
                    }
                    string expectedState = PageViewport.ActualWidth < 680 ? "Narrow" : "Standard";
                    if (ResponsiveStates.CurrentState?.Name != expectedState)
                    {
                        StartupDiagnostics.Stage($"responsive-state-smoke-failed page={page} width={PageViewport.ActualWidth} state={ResponsiveStates.CurrentState?.Name}");
                        throw new InvalidOperationException("Responsive controls did not follow the content viewport.");
                    }
                    if (page == "profile" && width == 560)
                    {
                        var description = (FrameworkElement)ProfileNameLayout.Children[0];
                        double editorTop = ProfileNameEditor.TransformToVisual(ProfileNameLayout).TransformPoint(new Point()).Y;
                        if (editorTop < description.ActualHeight
                            || Math.Abs(ProfileNameEditor.ActualWidth - ProfileNameLayout.ActualWidth) > 1)
                        {
                            StartupDiagnostics.Stage($"responsive-form-smoke-failed top={editorTop} label-height={description.ActualHeight} editor-width={ProfileNameEditor.ActualWidth} form-width={ProfileNameLayout.ActualWidth}");
                            throw new InvalidOperationException("Narrow profile editor was not stacked at full width.");
                        }
                    }
                    if (page == "profile")
                    {
                        foreach (GridView selector in new[] { CharacterSelector, BubbleSelector, ThrowableSelector })
                            VerifyCompactSelectionGrid(selector);
                    }
                }
            }
            ShowPage("about");
            AboutPage.UpdateLayout();
            LanguageSettingsLayout.StartBringIntoView(new BringIntoViewOptions { AnimationDesired = false });
            await WaitForNextFrameAsync();
            await WaitForNextFrameAsync();
            MainRoot.UpdateLayout();
            FontIcon? languageIcon = FindVisualChild<FontIcon>(LanguageSettingsLayout);
            if (languageIcon is null || languageIcon.ActualWidth <= 0 || languageIcon.ActualHeight <= 0
                || !languageIcon.FontFamily.Source.Contains("Segoe MDL2 Assets", StringComparison.Ordinal))
            {
                StartupDiagnostics.Stage($"window-symbol-smoke-failed font={languageIcon?.FontFamily.Source} size={languageIcon?.ActualWidth}x{languageIcon?.ActualHeight}");
                throw new InvalidOperationException("The language icon did not resolve the Windows 10 symbol fallback.");
            }
            StartupDiagnostics.Stage("window-compatibility-smoke-complete opaque-background=true symbol-fallback=true");
            StartupDiagnostics.Stage("responsive-window-smoke-complete widths=560,720,1040 themes=dark,light,system");
        }
        finally
        {
            MainRoot.RequestedTheme = originalTheme;
            ApplyBackdrop();
            ViewModel.IsStoreLoading = wasLoading;
            AppWindow.Resize(originalSize);
            ShowPage("profile");
        }
    }

    private static void VerifyCompactSelectionGrid(GridView selector)
    {
        ResponsiveSelectionPanel? panel = FindVisualChild<ResponsiveSelectionPanel>(selector);
        if (panel is null || panel.Children.Count != selector.Items.Count || panel.Children.Count == 0)
            throw new InvalidOperationException("Profile choices were not realized for the compact-grid check.");

        var bounds = new List<Rect>();
        foreach (UIElement child in panel.Children)
        {
            var tile = (FrameworkElement)child;
            Rect current = tile.TransformToVisual(panel).TransformBounds(
                new Rect(0, 0, tile.ActualWidth, tile.ActualHeight));
            if (current.Width <= 0 || current.Width > 144.01
                || current.Left < -1 || current.Right > panel.ActualWidth + 1
                || current.Top < -1 || current.Bottom > panel.ActualHeight + 1
                || (bounds.Count > 0 && Math.Abs(current.Width - bounds[0].Width) > 1))
            {
                StartupDiagnostics.Stage($"compact-grid-smoke-failed selector={selector.Name} tile={current} panel={panel.ActualWidth}x{panel.ActualHeight}");
                throw new InvalidOperationException("Profile choices were stretched or clipped, including the last row.");
            }
            if (bounds.Any(previous => current.Left < previous.Right - 1 && current.Right > previous.Left + 1
                && current.Top < previous.Bottom - 1 && current.Bottom > previous.Top + 1))
                throw new InvalidOperationException("Compact profile choices overlapped.");
            bounds.Add(current);
        }

        int columns = bounds.Count(item => Math.Abs(item.Top - bounds[0].Top) <= 1);
        int? expectedColumns = panel.ActualWidth >= 672 ? 5
            : panel.ActualWidth is >= 264 and < 400 ? 2 : null;
        if (expectedColumns is { } expected && columns != Math.Min(expected, bounds.Count))
        {
            StartupDiagnostics.Stage($"compact-grid-column-smoke-failed selector={selector.Name} width={panel.ActualWidth} expected={expected} actual={columns}");
            throw new InvalidOperationException("Profile choices did not use the expected wide or narrow column count.");
        }
        for (int index = 0; index < bounds.Count; index++)
        {
            if (Math.Abs(bounds[index].Left - bounds[index % columns].Left) > 1)
                throw new InvalidOperationException("The last profile row did not retain the shared column positions.");
        }
    }
}
