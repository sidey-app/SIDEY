using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Sidey.App.Controls;
using Sidey.Core.Domain;
using Sidey.Platform.Windows;
using Windows.Foundation;
using Windows.Graphics;

namespace Sidey.App.Views;

public sealed partial class MainWindow
{
    internal async Task VerifySkeletonLoadingSmokeAsync()
    {
        (string Page, FrameworkElement Skeleton, Func<bool> Get, Action<bool> Set)[] regions =
        [
            ("profile", CharacterSkeleton, () => ViewModel.IsCharacterSelectionsLoading, value => ViewModel.IsCharacterSelectionsLoading = value),
            ("profile", BubbleSkeleton, () => ViewModel.IsBubbleSelectionsLoading, value => ViewModel.IsBubbleSelectionsLoading = value),
            ("profile", ThrowableSkeleton, () => ViewModel.IsThrowableSelectionsLoading, value => ViewModel.IsThrowableSelectionsLoading = value),
            ("groups", RoomsSkeleton, () => ViewModel.IsRoomsLoading, value => ViewModel.IsRoomsLoading = value),
            ("store", StoreSkeletonRepeater, () => ViewModel.IsStoreLoading, value => ViewModel.IsStoreLoading = value),
        ];
        bool[] originalLoading = [.. regions.Select(region => region.Get())];
        SizeInt32 originalSize = AppWindow.Size;
        ElementTheme originalTheme = MainRoot.RequestedTheme;
        int originalKind = ViewModel.SelectedStoreKindIndex;
        try
        {
            ViewModel.SelectedStoreKindIndex = (int)CommerceProductKind.Throwable;
            foreach ((string Page, FrameworkElement Skeleton, Func<bool> Get, Action<bool> Set) region in regions)
                region.Set(false);
            foreach (ElementTheme theme in new[] { ElementTheme.Light, ElementTheme.Dark })
            {
                MainRoot.RequestedTheme = theme;
                foreach (int width in new[] { 560, 1040 })
                {
                    double scale = MainRoot.XamlRoot.RasterizationScale;
                    AppWindow.ResizeClient(new SizeInt32((int)Math.Round(width * scale), (int)Math.Round(700 * scale)));
                    await WaitForNextFrameAsync();
                    foreach ((string Page, FrameworkElement Skeleton, Func<bool> Get, Action<bool> Set) region in regions)
                    {
                        ShowPage(region.Page);
                        region.Set(true);
                        MainRoot.UpdateLayout();
                        region.Skeleton.StartBringIntoView(new BringIntoViewOptions { AnimationDesired = false });
                        await WaitForNextFrameAsync();
                        await WaitForNextFrameAsync();
                        MainRoot.UpdateLayout();
                        StartupDiagnostics.Stage($"skeleton-smoke-visibility region={region.Skeleton.Name} states={string.Join(',', regions.Select(item => item.Skeleton.Visibility))}");
                        if (region.Skeleton.Visibility != Visibility.Visible
                            || regions.Any(other => other.Page == region.Page && other.Skeleton != region.Skeleton && other.Skeleton.Visibility != Visibility.Collapsed))
                            throw new InvalidOperationException("A skeleton followed another region's loading state.");
                        SkeletonBar bar = FindVisualChild<SkeletonBar>(region.Skeleton)
                            ?? throw new InvalidOperationException("Loading skeleton is missing.");
                        StartupDiagnostics.Stage($"skeleton-smoke-size region={region.Skeleton.Name} bar={bar.ActualWidth}x{bar.ActualHeight} content={((FrameworkElement)bar.Content).ActualWidth}x{((FrameworkElement)bar.Content).ActualHeight}");
                        if (bar.Content is not FrameworkElement fill
                            || fill.ActualWidth < bar.ActualWidth - 1 || fill.ActualHeight < bar.ActualHeight - 1
                            || bar.ActualWidth <= 0 || bar.ActualHeight <= 0)
                            throw new InvalidOperationException("Skeleton fill does not occupy its reserved space.");
                        VerifySkeletonBounds(region.Skeleton, region.Skeleton);
                        var rendered = new RenderTargetBitmap();
                        await rendered.RenderAsync(bar);
                        byte[] pixels = System.Runtime.InteropServices.WindowsRuntime.WindowsRuntimeBufferExtensions.ToArray(
                            await rendered.GetPixelsAsync());
                        int visiblePixels = 0;
                        for (int offset = 3; offset < pixels.Length; offset += 4)
                        {
                            if (pixels[offset] >= 32)
                                visiblePixels++;
                        }
                        StartupDiagnostics.Stage($"skeleton-smoke-pixels region={region.Skeleton.Name} bytes={pixels.Length} visible={visiblePixels}");
                        if (pixels.Length == 0 || visiblePixels < pixels.Length / 8)
                            throw new InvalidOperationException("Skeleton loading indicator is empty or too faint.");
                        double loadingExtent = StorePage.ExtentHeight;
                        region.Set(false);
                        await WaitForNextFrameAsync();
                        await WaitForNextFrameAsync();
                        MainRoot.UpdateLayout();
                        StartupDiagnostics.Stage($"skeleton-smoke-hidden region={region.Skeleton.Name} visibility={region.Skeleton.Visibility} pulse={bar.IsPulseRunning} extent={StorePage.ExtentHeight} previous={loadingExtent}");
                        if (region.Skeleton.Visibility != Visibility.Collapsed || bar.IsPulseRunning)
                            throw new InvalidOperationException("Completed content left its skeleton or pulse visible.");
                        if (region.Page == "store" && Math.Abs(StorePage.ExtentHeight - loadingExtent) > 1)
                            throw new InvalidOperationException("Loading completion changed the store height.");
                        StartupDiagnostics.Stage($"skeleton-loading-smoke-complete region={region.Skeleton.Name} theme={theme} width={width} visible-pixels={visiblePixels}");
                    }
                }
            }
        }
        finally
        {
            MainRoot.RequestedTheme = originalTheme;
            ViewModel.SelectedStoreKindIndex = originalKind;
            for (int index = 0; index < regions.Length; index++)
                regions[index].Set(originalLoading[index]);
            AppWindow.Resize(originalSize);
            ShowPage("profile");
            HomePage.ChangeView(null, 0, null, disableAnimation: true);
        }
    }

    private static void VerifySkeletonBounds(DependencyObject node, FrameworkElement region)
    {
        if (node is SkeletonBar bar)
        {
            Point position = bar.TransformToVisual(region).TransformPoint(new Point());
            if (position.X < -1 || position.X + bar.ActualWidth > region.ActualWidth + 1)
            {
                StartupDiagnostics.Stage($"skeleton-bounds-smoke-failed region={region.Name} x={position.X} width={bar.ActualWidth} available={region.ActualWidth}");
                throw new InvalidOperationException("A loading placeholder overflows its region.");
            }
        }
        for (int index = 0; index < Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(node); index++)
            VerifySkeletonBounds(Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(node, index), region);
    }
}
