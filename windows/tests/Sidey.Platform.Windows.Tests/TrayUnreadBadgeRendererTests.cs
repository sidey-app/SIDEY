
using System.Runtime.InteropServices;

namespace Sidey.Platform.Windows.Tests;

public sealed class TrayUnreadBadgeRendererTests
{
    [Fact]
    public void PaintsAnOpaqueRedDotInTheUpperRightCorner()
    {
        const int Size = 32;
        byte[] pixels = new byte[Size * Size * 4];

        TrayUnreadBadgeRenderer.Apply(pixels, Size, Size);

        int center = ((7 * Size) + 24) * 4;
        Assert.True(pixels[center + 2] >= 220);
        Assert.True(pixels[center + 1] <= 40);
        Assert.True(pixels[center] <= 60);
        Assert.Equal(255, pixels[center + 3]);

        int lowerLeft = ((28 * Size) + 3) * 4;
        Assert.Equal([0, 0, 0, 0], pixels[lowerLeft..(lowerLeft + 4)]);
    }

    [Theory]
    [InlineData(16)]
    [InlineData(20)]
    [InlineData(24)]
    [InlineData(32)]
    public void SupportsCommonWindowsTrayIconSizes(int size)
    {
        byte[] pixels = new byte[size * size * 4];

        TrayUnreadBadgeRenderer.Apply(pixels, size, size);

        Assert.Contains(
            Enumerable.Range(0, pixels.Length / 4),
            index => pixels[(index * 4) + 2] >= 220
                && pixels[(index * 4) + 1] <= 40
                && pixels[(index * 4) + 3] > 0);
    }

    [Fact]
    public void CreatesANativeUnreadIconFromAWindowsIcon()
    {
        nint source = LoadIcon(nint.Zero, new nint(32512));
        Assert.NotEqual(nint.Zero, source);

        nint unread = TrayIconService.CreateUnreadIcon(source);
        try
        {
            Assert.NotEqual(nint.Zero, unread);
        }
        finally
        {
            if (unread != nint.Zero)
            {
                DestroyIcon(unread);
            }
        }
    }

    [DllImport("user32.dll")]
    private static extern nint LoadIcon(nint instance, nint iconName);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(nint icon);
}
