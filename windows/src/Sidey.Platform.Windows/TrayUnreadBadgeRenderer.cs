namespace Sidey.Platform.Windows;

internal static class TrayUnreadBadgeRenderer
{
    private const int SamplesPerAxis = 4;

    public static void Apply(Span<byte> bgraPixels, int width, int height)
    {
        if (width <= 0 || height <= 0 || bgraPixels.Length < width * height * 4)
        {
            throw new ArgumentException("The tray icon pixel buffer is invalid.", nameof(bgraPixels));
        }

        double scale = Math.Min(width, height);
        double outerRadius = Math.Max(2.5d, scale * 0.19d);
        double innerRadius = outerRadius * 0.72d;
        double margin = Math.Max(1d, scale * 0.04d);
        double centerX = width - margin - outerRadius;
        double centerY = margin + outerRadius;

        PaintCircle(bgraPixels, width, height, centerX, centerY, outerRadius, 255, 255, 255);
        PaintCircle(bgraPixels, width, height, centerX, centerY, innerRadius, 232, 17, 35);
    }

    private static void PaintCircle(
        Span<byte> pixels,
        int width,
        int height,
        double centerX,
        double centerY,
        double radius,
        byte red,
        byte green,
        byte blue)
    {
        int left = Math.Max(0, (int)Math.Floor(centerX - radius - 1d));
        int top = Math.Max(0, (int)Math.Floor(centerY - radius - 1d));
        int right = Math.Min(width - 1, (int)Math.Ceiling(centerX + radius + 1d));
        int bottom = Math.Min(height - 1, (int)Math.Ceiling(centerY + radius + 1d));
        double radiusSquared = radius * radius;

        for (int y = top; y <= bottom; y++)
        {
            for (int x = left; x <= right; x++)
            {
                int coveredSamples = 0;
                for (int sampleY = 0; sampleY < SamplesPerAxis; sampleY++)
                {
                    double py = y + ((sampleY + 0.5d) / SamplesPerAxis);
                    for (int sampleX = 0; sampleX < SamplesPerAxis; sampleX++)
                    {
                        double px = x + ((sampleX + 0.5d) / SamplesPerAxis);
                        double dx = px - centerX;
                        double dy = py - centerY;
                        if ((dx * dx) + (dy * dy) <= radiusSquared)
                        {
                            coveredSamples++;
                        }
                    }
                }

                if (coveredSamples == 0)
                {
                    continue;
                }

                double opacity = coveredSamples / (double)(SamplesPerAxis * SamplesPerAxis);
                Blend(pixels, ((y * width) + x) * 4, red, green, blue, opacity);
            }
        }
    }

    private static void Blend(
        Span<byte> pixels,
        int offset,
        byte red,
        byte green,
        byte blue,
        double sourceAlpha)
    {
        double destinationAlpha = pixels[offset + 3] / 255d;
        double outputAlpha = sourceAlpha + (destinationAlpha * (1d - sourceAlpha));
        if (outputAlpha <= 0d)
        {
            return;
        }

        pixels[offset] = BlendChannel(blue, pixels[offset], sourceAlpha, destinationAlpha, outputAlpha);
        pixels[offset + 1] = BlendChannel(green, pixels[offset + 1], sourceAlpha, destinationAlpha, outputAlpha);
        pixels[offset + 2] = BlendChannel(red, pixels[offset + 2], sourceAlpha, destinationAlpha, outputAlpha);
        pixels[offset + 3] = (byte)Math.Round(outputAlpha * 255d, MidpointRounding.AwayFromZero);
    }

    private static byte BlendChannel(
        byte source,
        byte destination,
        double sourceAlpha,
        double destinationAlpha,
        double outputAlpha) =>
        (byte)Math.Round(
            ((source * sourceAlpha)
                + (destination * destinationAlpha * (1d - sourceAlpha)))
            / outputAlpha,
            MidpointRounding.AwayFromZero);
}
