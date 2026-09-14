using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
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
        bool wasLoading = ViewModel.IsRemoteContentLoading;
        try
        {
            ViewModel.IsRemoteContentLoading = false;
            foreach (ElementTheme theme in new[] { ElementTheme.Dark, ElementTheme.Light, ElementTheme.Default })
            {
                MainRoot.RequestedTheme = theme;
                await WaitForNextFrameAsync();
                await WaitForNextFrameAsync();
                TitleBarTheme expected = MainRoot.ActualTheme == ElementTheme.Dark ? TitleBarTheme.Dark : TitleBarTheme.Light;
                if (AppWindow.TitleBar.PreferredTheme != expected)
                {
                    StartupDiagnostics.Stage($"caption-theme-smoke-failed requested={theme} actual={MainRoot.ActualTheme} caption={AppWindow.TitleBar.PreferredTheme}");
                    throw new InvalidOperationException("Caption theme did not follow the actual content theme.");
                }
            }
            foreach (string page in new[] { "profile", "store", "settings" })
            {
                ShowPage(page);
                foreach (int width in new[] { 1040, 720, 560, 1040 })
                {
                    double scale = MainRoot.XamlRoot.RasterizationScale;
                    AppWindow.ResizeClient(new SizeInt32((int)Math.Round(width * scale), (int)Math.Round(700 * scale)));
                    await WaitForNextFrameAsync();
                    await WaitForNextFrameAsync();
                    MainRoot.UpdateLayout();
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
                        var first = (GridViewItem)CharacterSelector.ContainerFromIndex(0);
                        var second = (GridViewItem)CharacterSelector.ContainerFromIndex(1);
                        var third = (GridViewItem)CharacterSelector.ContainerFromIndex(2);
                        Point firstPosition = first.TransformToVisual(CharacterSelector).TransformPoint(new Point());
                        Point secondPosition = second.TransformToVisual(CharacterSelector).TransformPoint(new Point());
                        Point thirdPosition = third.TransformToVisual(CharacterSelector).TransformPoint(new Point());
                        if (Math.Abs(firstPosition.Y - secondPosition.Y) > 1
                            || thirdPosition.Y < firstPosition.Y + first.ActualHeight - 1
                            || secondPosition.X + second.ActualWidth > CharacterSelector.ActualWidth + 1)
                        {
                            StartupDiagnostics.Stage($"responsive-grid-smoke-failed first={firstPosition} second={secondPosition} third={thirdPosition} width={CharacterSelector.ActualWidth}");
                            throw new InvalidOperationException("Narrow profile choices were clipped or did not wrap into two columns.");
                        }
                    }
                }
            }
            StartupDiagnostics.Stage("responsive-window-smoke-complete widths=560,720,1040 themes=dark,light,system");
        }
        finally
        {
            MainRoot.RequestedTheme = originalTheme;
            ViewModel.IsRemoteContentLoading = wasLoading;
            AppWindow.Resize(originalSize);
            ShowPage("profile");
        }
    }
}
