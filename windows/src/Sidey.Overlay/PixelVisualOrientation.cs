using Sidey.Core.Domain;

namespace Sidey.Overlay;

internal static class PixelVisualOrientation
{
    internal static PremultipliedVisual Apply(PremultipliedVisual source, OverlayEdge edge)
    {
        if (edge == OverlayEdge.Bottom)
        {
            return source;
        }

        int width = edge is OverlayEdge.Left or OverlayEdge.Right
            ? source.Height
            : source.Width;
        int height = edge is OverlayEdge.Left or OverlayEdge.Right
            ? source.Width
            : source.Height;
        byte[] pixels = new byte[checked(width * height * 4)];
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                (int sourceX, int sourceY) = SourceCoordinate(source, edge, x, y);
                int sourceIndex = ((sourceY * source.Width) + sourceX) * 4;
                int destinationIndex = ((y * width) + x) * 4;
                source.Pixels.AsSpan(sourceIndex, 4).CopyTo(pixels.AsSpan(destinationIndex, 4));
            }
        }

        Array.Clear(source.Pixels);
        return new PremultipliedVisual(
            pixels,
            width,
            height,
            source.BubblePalette,
            RotateBodyBounds(source, edge));
    }

    private static PixelVisualBodyBounds? RotateBodyBounds(
        PremultipliedVisual source,
        OverlayEdge edge)
    {
        if (source.BubbleBodyBounds is not { } body)
        {
            return null;
        }

        return edge switch
        {
            OverlayEdge.Top => new PixelVisualBodyBounds(
                source.Width - body.X - body.Width,
                source.Height - body.Y - body.Height,
                body.Width,
                body.Height),
            OverlayEdge.Left => new PixelVisualBodyBounds(
                source.Height - body.Y - body.Height,
                body.X,
                body.Height,
                body.Width),
            OverlayEdge.Right => new PixelVisualBodyBounds(
                body.Y,
                source.Width - body.X - body.Width,
                body.Height,
                body.Width),
            _ => throw new ArgumentOutOfRangeException(nameof(edge)),
        };
    }

    private static (int X, int Y) SourceCoordinate(
        PremultipliedVisual source,
        OverlayEdge edge,
        int x,
        int y) => edge switch
        {
            OverlayEdge.Top => (source.Width - 1 - x, source.Height - 1 - y),
            OverlayEdge.Left => (y, source.Height - 1 - x),
            OverlayEdge.Right => (source.Width - 1 - y, x),
            _ => throw new ArgumentOutOfRangeException(nameof(edge)),
        };
}
