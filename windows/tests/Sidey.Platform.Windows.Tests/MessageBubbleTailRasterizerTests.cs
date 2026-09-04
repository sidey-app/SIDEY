using Sidey.Core.Domain;
using Sidey.Core.Overlay;
using Sidey.Overlay;
using Sidey.Platform.Windows;

namespace Sidey.Platform.Windows.Tests;

public sealed class MessageBubbleTailRasterizerTests
{
    [Theory]
    [InlineData(OverlayEdge.Bottom, 1d)]
    [InlineData(OverlayEdge.Bottom, 2d)]
    [InlineData(OverlayEdge.Top, 1.25d)]
    [InlineData(OverlayEdge.Left, 1.5d)]
    [InlineData(OverlayEdge.Right, 2d)]
    public void TailPixelsRemainConnectedToTheBubbleBody(
        OverlayEdge edge,
        double scale)
    {
        var renderBounds = new NativePixelRect(0, 0, 96, 96);
        var body = new RectD(24, 24, 48, 48);
        byte[] pixels = new byte[renderBounds.Width * renderBounds.Height * 4];
        FillBody(pixels, renderBounds, body);
        MessageBubbleTail tail = CreateTail(edge, body, scale);

        MessageBubbleTailRasterizer.Composite(
            pixels,
            renderBounds,
            tail,
            body,
            borderWidth: scale);

        HashSet<(int X, int Y)> connected = ConnectedPixels(
            pixels,
            renderBounds,
            ((int)body.MidX, (int)body.MidY));
        Assert.Contains(
            PixelsNear(tail.Tip, renderBounds),
            point => AlphaAt(pixels, renderBounds, point.X, point.Y) > 0
                && connected.Contains(point));
        AssertPremultiplied(pixels);
    }

    [Fact]
    public void RasterizationDoesNotAllocatePerFrame()
    {
        var renderBounds = new NativePixelRect(0, 0, 96, 96);
        var body = new RectD(24, 24, 48, 48);
        var tail = CreateTail(OverlayEdge.Bottom, body, scale: 1d);
        byte[] pixels = new byte[renderBounds.Width * renderBounds.Height * 4];
        MessageBubbleTailRasterizer.Composite(pixels, renderBounds, tail, body, 1d);

        long before = GC.GetAllocatedBytesForCurrentThread();
        for (int iteration = 0; iteration < 100; iteration++)
        {
            MessageBubbleTailRasterizer.Composite(pixels, renderBounds, tail, body, 1d);
        }
        long allocated = GC.GetAllocatedBytesForCurrentThread() - before;

        Assert.Equal(0, allocated);
    }

    private static MessageBubbleTail CreateTail(
        OverlayEdge edge,
        RectD body,
        double scale)
    {
        double senderTangent = edge is OverlayEdge.Bottom or OverlayEdge.Top
            ? body.MidX
            : body.MidY;
        return MessageBubbleLayoutPolicy.Tail(
            edge,
            body,
            senderTangent,
            tailHeight: 8d * scale,
            halfBase: 6d * scale,
            baseInset: 10d * scale,
            baseOverlap: 2d * scale);
    }

    private static void FillBody(
        byte[] pixels,
        NativePixelRect renderBounds,
        RectD body)
    {
        for (int y = (int)body.MinY; y < (int)body.MaxY; y++)
        {
            for (int x = (int)body.MinX; x < (int)body.MaxX; x++)
            {
                int index = ((y * renderBounds.Width) + x) * 4;
                pixels[index] = 242;
                pixels[index + 1] = 242;
                pixels[index + 2] = 242;
                pixels[index + 3] = 242;
            }
        }
    }

    private static HashSet<(int X, int Y)> ConnectedPixels(
        byte[] pixels,
        NativePixelRect renderBounds,
        (int X, int Y) start)
    {
        var visited = new HashSet<(int X, int Y)> { start };
        var pending = new Queue<(int X, int Y)>([start]);
        while (pending.TryDequeue(out (int X, int Y) point))
        {
            foreach ((int X, int Y) candidate in Neighbors(point, renderBounds))
            {
                if (AlphaAt(pixels, renderBounds, candidate.X, candidate.Y) > 0
                    && visited.Add(candidate))
                {
                    pending.Enqueue(candidate);
                }
            }
        }

        return visited;
    }

    private static IEnumerable<(int X, int Y)> Neighbors(
        (int X, int Y) point,
        NativePixelRect renderBounds)
    {
        for (int offsetY = -1; offsetY <= 1; offsetY++)
        {
            for (int offsetX = -1; offsetX <= 1; offsetX++)
            {
                if (offsetX == 0 && offsetY == 0)
                {
                    continue;
                }

                int x = point.X + offsetX;
                int y = point.Y + offsetY;
                if (x >= 0 && x < renderBounds.Width && y >= 0 && y < renderBounds.Height)
                {
                    yield return (x, y);
                }
            }
        }
    }

    private static IEnumerable<(int X, int Y)> PixelsNear(
        PointD point,
        NativePixelRect renderBounds)
    {
        int centerX = (int)Math.Round(point.X);
        int centerY = (int)Math.Round(point.Y);
        for (int y = centerY - 2; y <= centerY + 2; y++)
        {
            for (int x = centerX - 2; x <= centerX + 2; x++)
            {
                if (x >= 0 && x < renderBounds.Width && y >= 0 && y < renderBounds.Height)
                {
                    yield return (x, y);
                }
            }
        }
    }

    private static byte AlphaAt(
        byte[] pixels,
        NativePixelRect renderBounds,
        int x,
        int y) => pixels[(((y * renderBounds.Width) + x) * 4) + 3];

    private static void AssertPremultiplied(byte[] pixels)
    {
        for (int index = 0; index < pixels.Length; index += 4)
        {
            byte alpha = pixels[index + 3];
            Assert.True(pixels[index] <= alpha);
            Assert.True(pixels[index + 1] <= alpha);
            Assert.True(pixels[index + 2] <= alpha);
        }
    }
}
