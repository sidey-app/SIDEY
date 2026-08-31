using Sidey.Core.Domain;
using Sidey.Overlay;

namespace Sidey.Platform.Windows.Tests;

public sealed class LayeredHamsterFrameTests
{
    [Fact]
    public void FrameBuilderPremultipliesAndRepeatsPixelsAtIntegerScale()
    {
        var sheet = EmptySheet();
        SetPixel(sheet, frame: 0, x: 0, y: 0, b: 100, g: 50, r: 20, a: 128);

        var frame = LayeredHamsterRenderer.BuildFrame(
            sheet,
            frame: 0,
            scale: 2,
            flipHorizontally: false,
            OverlayEdge.Bottom);

        AssertPixel(frame, size: 48, x: 0, y: 0, b: 50, g: 25, r: 10, a: 128);
        AssertPixel(frame, size: 48, x: 1, y: 1, b: 50, g: 25, r: 10, a: 128);
    }

    [Theory]
    [InlineData(OverlayEdge.Bottom, 2, 3)]
    [InlineData(OverlayEdge.Top, 21, 20)]
    [InlineData(OverlayEdge.Left, 20, 2)]
    [InlineData(OverlayEdge.Right, 3, 21)]
    public void FrameBuilderRotatesFeetTowardSelectedEdge(
        OverlayEdge edge,
        int expectedX,
        int expectedY)
    {
        var sheet = EmptySheet();
        SetPixel(sheet, frame: 0, x: 2, y: 3, b: 255, g: 0, r: 0, a: 255);

        var frame = LayeredHamsterRenderer.BuildFrame(
            sheet,
            frame: 0,
            scale: 1,
            flipHorizontally: false,
            edge);

        AssertPixel(frame, size: 24, expectedX, expectedY, b: 255, g: 0, r: 0, a: 255);
    }

    [Fact]
    public void FrameBuilderFlipsBeforeApplyingEdgeRotation()
    {
        var sheet = EmptySheet();
        SetPixel(sheet, frame: 0, x: 2, y: 3, b: 255, g: 0, r: 0, a: 255);

        var frame = LayeredHamsterRenderer.BuildFrame(
            sheet,
            frame: 0,
            scale: 1,
            flipHorizontally: true,
            OverlayEdge.Left);

        AssertPixel(frame, size: 24, x: 20, y: 21, b: 255, g: 0, r: 0, a: 255);
    }

    private static byte[] EmptySheet() => new byte[240 * 24 * 4];

    private static void SetPixel(
        byte[] sheet,
        int frame,
        int x,
        int y,
        byte b,
        byte g,
        byte r,
        byte a)
    {
        var index = ((y * 240) + (frame * 24) + x) * 4;
        sheet[index] = b;
        sheet[index + 1] = g;
        sheet[index + 2] = r;
        sheet[index + 3] = a;
    }

    private static void AssertPixel(
        byte[] frame,
        int size,
        int x,
        int y,
        byte b,
        byte g,
        byte r,
        byte a)
    {
        var index = ((y * size) + x) * 4;
        Assert.Equal(b, frame[index]);
        Assert.Equal(g, frame[index + 1]);
        Assert.Equal(r, frame[index + 2]);
        Assert.Equal(a, frame[index + 3]);
    }
}
