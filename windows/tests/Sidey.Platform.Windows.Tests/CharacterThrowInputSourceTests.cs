using Sidey.Platform.Windows;

namespace Sidey.Platform.Windows.Tests;

public sealed class CharacterThrowInputSourceTests
{
    [Fact]
    public void InputUsesBoundedPerCharacterHotspotsAndNoGlobalMouseHook()
    {
        var thread = Read("NativeOverlayWindowThread.cs");
        var window = Read("NativeOverlayWindow.cs");

        Assert.Equal(11, NativeOverlayWindowThread.MaximumTargetHotspots);
        Assert.Contains("WM_RBUTTONUP", window, StringComparison.Ordinal);
        Assert.Contains("_targetHotspotWindows", thread, StringComparison.Ordinal);
        Assert.DoesNotContain("SetWindowsHookEx", thread + window, StringComparison.Ordinal);
        Assert.DoesNotContain("SendInput", thread + window, StringComparison.Ordinal);
    }

    [Fact]
    public void RightClickTargetingWindowIsTenSecondsAndSettingDefaultsOff()
    {
        var session = Read("NativePixelWorldSession.cs");

        Assert.Contains("TimeSpan.FromSeconds(10)", session, StringComparison.Ordinal);
        Assert.Contains("!_requiresRightClickToThrow || _throwTargetingActive", session, StringComparison.Ordinal);
        Assert.False(Sidey.Core.Domain.AppPreferences.Default.RequiresRightClickToThrow);
    }

    private static string Read(string name) =>
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "TestAssets", name));
}
