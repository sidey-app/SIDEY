using Sidey.Platform.Windows;

namespace Sidey.Platform.Windows.Tests;

public sealed class TrayMenuStateTests
{
    [Theory]
    [InlineData(false, true, 0x0000u)]
    [InlineData(true, true, 0x0008u)]
    [InlineData(false, false, 0x0001u)]
    [InlineData(true, false, 0x0009u)]
    public void NativeMenuFlagsUseTheWindowsCheckMark(
        bool isChecked,
        bool isEnabled,
        uint expected)
    {
        Assert.Equal(expected, TrayIconService.NativeMenuFlags(isChecked, isEnabled));
    }

    [Theory]
    [InlineData(true, false)]
    [InlineData(false, true)]
    public void OverlayHiddenCheckStateIsCheckedOnlyWhileHidden(
        bool overlayVisible,
        bool expected)
    {
        Assert.Equal(expected, TrayIconService.OverlayHiddenCheckState(overlayVisible));
    }
}
