using Sidey.Core.Overlay;
using Sidey.Platform.Windows;

namespace Sidey.Overlay;

internal static class MessageBubbleTailRasterizer
{
    private const byte FillAlpha = 242;
    private const byte BorderAlpha = 41;
    private const byte BorderRed = 20;
    private const byte BorderGreen = 23;
    private const byte BorderBlue = 31;

    internal static void Composite(
        Span<byte> destination,
        NativePixelRect renderBounds,
        MessageBubbleTail tail,
        RectD bodyBounds,
        double borderWidth)
    {
        int requiredLength = checked(renderBounds.Width * renderBounds.Height * 4);
        if (destination.Length < requiredLength)
        {
            throw new ArgumentException("The destination buffer is smaller than the render bounds.", nameof(destination));
        }

        RasterizeTriangle(
            destination,
            renderBounds,
            tail.BaseStart,
            tail.Tip,
            tail.BaseEnd,
            bodyBounds);
        RasterizeLine(destination, renderBounds, tail.BaseStart, tail.Tip, borderWidth, bodyBounds);
        RasterizeLine(destination, renderBounds, tail.Tip, tail.BaseEnd, borderWidth, bodyBounds);
    }

    private static void RasterizeTriangle(
        Span<byte> destination,
        NativePixelRect renderBounds,
        PointD first,
        PointD second,
        PointD third,
        RectD bodyBounds)
    {
        int minimumX = (int)Math.Floor(Math.Min(first.X, Math.Min(second.X, third.X)));
        int maximumX = (int)Math.Ceiling(Math.Max(first.X, Math.Max(second.X, third.X)));
        int minimumY = (int)Math.Floor(Math.Min(first.Y, Math.Min(second.Y, third.Y)));
        int maximumY = (int)Math.Ceiling(Math.Max(first.Y, Math.Max(second.Y, third.Y)));
        for (int y = minimumY; y < maximumY; y++)
        {
            for (int x = minimumX; x < maximumX; x++)
            {
                int coveredSamples = CoveredTriangleSamples(x, y, first, second, third);
                if (coveredSamples == 0)
                {
                    continue;
                }

                double coverage = coveredSamples / 4d;
                if (ContainsPixelCenter(bodyBounds, x, y))
                {
                    ReplaceWithFill(destination, renderBounds, x, y, coverage);
                }
                else
                {
                    BlendPixel(
                        destination,
                        renderBounds,
                        x,
                        y,
                        255,
                        255,
                        255,
                        FillAlpha,
                        coverage);
                }
            }
        }
    }

    private static int CoveredTriangleSamples(
        int x,
        int y,
        PointD first,
        PointD second,
        PointD third)
    {
        int coveredSamples = 0;
        for (int sampleY = 0; sampleY < 2; sampleY++)
        {
            for (int sampleX = 0; sampleX < 2; sampleX++)
            {
                var point = new PointD(
                    x + ((sampleX + 0.5d) / 2d),
                    y + ((sampleY + 0.5d) / 2d));
                if (PointInTriangle(point, first, second, third))
                {
                    coveredSamples++;
                }
            }
        }

        return coveredSamples;
    }

    private static void RasterizeLine(
        Span<byte> destination,
        NativePixelRect renderBounds,
        PointD start,
        PointD end,
        double width,
        RectD bodyBounds)
    {
        double radius = Math.Max(0.5d, width / 2d);
        int minimumX = (int)Math.Floor(Math.Min(start.X, end.X) - radius);
        int maximumX = (int)Math.Ceiling(Math.Max(start.X, end.X) + radius);
        int minimumY = (int)Math.Floor(Math.Min(start.Y, end.Y) - radius);
        int maximumY = (int)Math.Ceiling(Math.Max(start.Y, end.Y) + radius);
        double radiusSquared = radius * radius;
        for (int y = minimumY; y < maximumY; y++)
        {
            for (int x = minimumX; x < maximumX; x++)
            {
                int coveredSamples = CoveredLineSamples(
                    x,
                    y,
                    start,
                    end,
                    radiusSquared,
                    bodyBounds);
                if (coveredSamples > 0)
                {
                    BlendPixel(
                        destination,
                        renderBounds,
                        x,
                        y,
                        BorderRed,
                        BorderGreen,
                        BorderBlue,
                        BorderAlpha,
                        coveredSamples / 4d);
                }
            }
        }
    }

    private static int CoveredLineSamples(
        int x,
        int y,
        PointD start,
        PointD end,
        double radiusSquared,
        RectD bodyBounds)
    {
        int coveredSamples = 0;
        for (int sampleY = 0; sampleY < 2; sampleY++)
        {
            for (int sampleX = 0; sampleX < 2; sampleX++)
            {
                var point = new PointD(
                    x + ((sampleX + 0.5d) / 2d),
                    y + ((sampleY + 0.5d) / 2d));
                if (!Contains(bodyBounds, point)
                    && DistanceSquaredToSegment(point, start, end) <= radiusSquared)
                {
                    coveredSamples++;
                }
            }
        }

        return coveredSamples;
    }

    private static void ReplaceWithFill(
        Span<byte> destination,
        NativePixelRect renderBounds,
        int worldX,
        int worldY,
        double coverage)
    {
        if (!TryPixelIndex(renderBounds, worldX, worldY, out int index))
        {
            return;
        }

        double amount = Math.Clamp(coverage, 0d, 1d);
        destination[index] = Lerp(destination[index], FillAlpha, amount);
        destination[index + 1] = Lerp(destination[index + 1], FillAlpha, amount);
        destination[index + 2] = Lerp(destination[index + 2], FillAlpha, amount);
        destination[index + 3] = Lerp(destination[index + 3], FillAlpha, amount);
    }

    private static void BlendPixel(
        Span<byte> destination,
        NativePixelRect renderBounds,
        int worldX,
        int worldY,
        byte red,
        byte green,
        byte blue,
        byte alpha,
        double coverage)
    {
        if (!TryPixelIndex(renderBounds, worldX, worldY, out int index))
        {
            return;
        }

        byte effectiveAlpha = (byte)Math.Clamp((int)Math.Round(alpha * coverage), 0, 255);
        if (effectiveAlpha == 0)
        {
            return;
        }

        int inverseAlpha = 255 - effectiveAlpha;
        destination[index] = Blend(
            (byte)(blue * effectiveAlpha / 255),
            destination[index],
            inverseAlpha);
        destination[index + 1] = Blend(
            (byte)(green * effectiveAlpha / 255),
            destination[index + 1],
            inverseAlpha);
        destination[index + 2] = Blend(
            (byte)(red * effectiveAlpha / 255),
            destination[index + 2],
            inverseAlpha);
        destination[index + 3] = Blend(
            effectiveAlpha,
            destination[index + 3],
            inverseAlpha);
    }

    private static bool TryPixelIndex(
        NativePixelRect renderBounds,
        int worldX,
        int worldY,
        out int index)
    {
        int x = worldX - renderBounds.X;
        int y = worldY - renderBounds.Y;
        if (x < 0 || x >= renderBounds.Width || y < 0 || y >= renderBounds.Height)
        {
            index = 0;
            return false;
        }

        index = ((y * renderBounds.Width) + x) * 4;
        return true;
    }

    private static byte Lerp(byte start, byte end, double amount) =>
        (byte)Math.Clamp((int)Math.Round(start + ((end - start) * amount)), 0, 255);

    private static byte Blend(byte source, byte destination, int inverseAlpha) =>
        (byte)Math.Min(255, source + ((destination * inverseAlpha + 127) / 255));

    private static bool ContainsPixelCenter(RectD bounds, int x, int y) =>
        Contains(bounds, new PointD(x + 0.5d, y + 0.5d));

    private static bool Contains(RectD bounds, PointD point) =>
        point.X >= bounds.MinX
        && point.X < bounds.MaxX
        && point.Y >= bounds.MinY
        && point.Y < bounds.MaxY;

    private static bool PointInTriangle(PointD point, PointD first, PointD second, PointD third)
    {
        double firstCross = Cross(point, first, second);
        double secondCross = Cross(point, second, third);
        double thirdCross = Cross(point, third, first);
        bool hasNegative = firstCross < 0d || secondCross < 0d || thirdCross < 0d;
        bool hasPositive = firstCross > 0d || secondCross > 0d || thirdCross > 0d;
        return !(hasNegative && hasPositive);
    }

    private static double Cross(PointD point, PointD first, PointD second) =>
        ((point.X - second.X) * (first.Y - second.Y))
        - ((first.X - second.X) * (point.Y - second.Y));

    private static double DistanceSquaredToSegment(PointD point, PointD start, PointD end)
    {
        double deltaX = end.X - start.X;
        double deltaY = end.Y - start.Y;
        double lengthSquared = (deltaX * deltaX) + (deltaY * deltaY);
        if (lengthSquared <= double.Epsilon)
        {
            double pointDeltaX = point.X - start.X;
            double pointDeltaY = point.Y - start.Y;
            return (pointDeltaX * pointDeltaX) + (pointDeltaY * pointDeltaY);
        }

        double progress = Math.Clamp(
            (((point.X - start.X) * deltaX) + ((point.Y - start.Y) * deltaY))
                / lengthSquared,
            0d,
            1d);
        double nearestX = start.X + (progress * deltaX);
        double nearestY = start.Y + (progress * deltaY);
        double distanceX = point.X - nearestX;
        double distanceY = point.Y - nearestY;
        return (distanceX * distanceX) + (distanceY * distanceY);
    }
}
