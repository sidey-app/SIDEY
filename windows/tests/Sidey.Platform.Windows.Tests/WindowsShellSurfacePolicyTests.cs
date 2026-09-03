using Sidey.Platform.Windows;

namespace Sidey.Platform.Windows.Tests;

public sealed class WindowsShellSurfacePolicyTests
{
    [Theory]
    [InlineData("StartMenuExperienceHost", "Windows.UI.Core.CoreWindow")]
    [InlineData("SearchHost", "Windows.UI.Composition.DesktopWindowContentBridge")]
    [InlineData("ShellExperienceHost", "ControlCenterWindow")]
    [InlineData("WidgetBoard", "Windows.UI.Composition.DesktopWindowContentBridge")]
    [InlineData("MicrosoftStartFeedProvider", "Windows.UI.Composition.DesktopWindowContentBridge")]
    [InlineData("Widgets", "Windows.UI.Composition.DesktopWindowContentBridge")]
    [InlineData("explorer", "TopLevelWindowForOverflowXamlIsland")]
    [InlineData("explorer", "NotifyIconOverflowWindow")]
    [InlineData("explorer", "Shell_TrayWnd")]
    [InlineData("explorer", "Shell_SecondaryTrayWnd")]
    public void TaskbarShellSurfacesYieldOverlay(string processName, string windowClass)
    {
        Assert.True(WindowsShellSurfacePolicy.ShouldYield(processName, windowClass));
    }

    [Theory]
    [InlineData("Shell_TrayWnd")]
    [InlineData("Shell_SecondaryTrayWnd")]
    public void PersistentTaskbarsAreDetectedForInputYielding(string windowClass)
    {
        Assert.True(WindowsShellSurfacePolicy.IsTaskbarWindow(windowClass));
    }

    [Theory]
    [InlineData("explorer", "CabinetWClass")]
    [InlineData("notepad", "Notepad")]
    [InlineData("SIDEY", "SIDEY.NativeOverlayWindow")]
    public void NormalApplicationWindowsKeepOverlayTopmost(string processName, string windowClass)
    {
        Assert.False(WindowsShellSurfacePolicy.ShouldYield(processName, windowClass));
    }

    [Theory]
    [InlineData("#32768")]
    [InlineData("Microsoft.UI.Content.PopupWindowSiteBridge")]
    [InlineData("Xaml_WindowedPopupClass")]
    [InlineData("tooltips_class32")]
    public void TransientMenusAndTooltipsCoverTheOverlay(string windowClass)
    {
        Assert.True(WindowsShellSurfacePolicy.IsTransientPopup(windowClass));
    }

    [Theory]
    [InlineData("WindowsForms10.Window.8.app.0.2bf8098_r6_ad1")]
    [InlineData("Qt663QWindowPopupDropShadowSaveBits")]
    [InlineData("CustomTrayMenu")]
    public void PopupToolWindowsCoverTheOverlayEvenWithApplicationSpecificClasses(string windowClass)
    {
        var popupStyle = new IntPtr(unchecked((long)0x80000000));
        var toolWindowStyle = new IntPtr(0x80);

        Assert.True(WindowsShellSurfacePolicy.IsTransientPopup(
            windowClass,
            popupStyle,
            toolWindowStyle));
    }

    [Theory]
    [InlineData("CabinetWClass")]
    [InlineData("Notepad")]
    [InlineData("SIDEY.NativeOverlayWindow")]
    public void NormalTopLevelWindowsAreNotTransientPopups(string windowClass)
    {
        Assert.False(WindowsShellSurfacePolicy.IsTransientPopup(windowClass));
    }

    [Theory]
    [InlineData("SIDEY.NativeOverlayWindow")]
    [InlineData("Shell_TrayWnd")]
    [InlineData("Shell_SecondaryTrayWnd")]
    [InlineData("WorkerW")]
    public void PersistentOverlayAndShellWindowsAreExcludedFromGenericPopupDetection(string windowClass)
    {
        var popupStyle = new IntPtr(unchecked((long)0x80000000));
        var toolWindowStyle = new IntPtr(0x80);

        Assert.False(WindowsShellSurfacePolicy.IsTransientPopup(
            windowClass,
            popupStyle,
            toolWindowStyle));
    }
}
