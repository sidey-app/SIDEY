using System.Runtime.InteropServices;
using Sidey.Platform.Windows;

namespace Sidey.Platform.Windows.Tests;

public sealed class WindowsBorderlessWindowControllerTests
{
    [Fact]
    public void KeepsTheWholeClientAreaAtCommonDpiSizesAndRestoresNormalFrameOnDetach()
    {
        nint window = CreateWindowEx(0, "STATIC", "SIDEY frame test", 0x00CF0000,
            0, 0, 400, 100, 0, 0, 0, 0);
        Assert.NotEqual(nint.Zero, window);
        try
        {
            using (var frame = new WindowsBorderlessWindowController(window))
            {
                foreach ((int width, int height) in new[] { (400, 56), (500, 70), (600, 84), (800, 112) })
                {
                    Assert.True(SetWindowPos(window, 0, 0, 0, width, height, 0x0036));
                    Assert.True(GetClientRect(window, out Rect client));
                    Assert.Equal(width, client.Right - client.Left);
                    Assert.Equal(height, client.Bottom - client.Top);
                    // The area formerly occupied by the caption is now interactive content.
                    Assert.Equal((nint)1, SendMessage(window, 0x0084, 0, 0));
                }
            }

            Assert.True(SetWindowPos(window, 0, 0, 0, 400, 100, 0x0036));
            Assert.True(GetClientRect(window, out Rect restoredClient));
            Assert.True(restoredClient.Bottom - restoredClient.Top < 100);
        }
        finally
        {
            _ = DestroyWindow(window);
        }
    }

    [Fact]
    public void CanDisposeAfterNativeWindowDestruction()
    {
        nint window = CreateWindowEx(0, "STATIC", "SIDEY frame lifetime test", 0x00CF0000,
            0, 0, 400, 100, 0, 0, 0, 0);
        Assert.NotEqual(nint.Zero, window);
        using var frame = new WindowsBorderlessWindowController(window);
        Assert.True(DestroyWindow(window));
        frame.Dispose();
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint CreateWindowEx(uint exStyle, string className, string title, uint style,
        int x, int y, int width, int height, nint parent, nint menu, nint instance, nint parameter);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(nint window, nint after, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetClientRect(nint window, out Rect rect);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyWindow(nint window);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern nint SendMessage(nint window, uint message, nuint wParam, nint lParam);
}
