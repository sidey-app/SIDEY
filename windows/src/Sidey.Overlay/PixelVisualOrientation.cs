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

        var width = edge is OverlayEdge.Left or OverlayEdge.Right
            ? source.Height
            : source.Width;
        var height = edge is OverlayEdge.Left or OverlayEdge.Right
            ? source.Width
            : source.Height;
        var pixels = new byte[checked(width * height * 4)];
        for (var y = 0; y < height; y++)
        {
            for (var x = 0; x < width; x++)
            {
                var (sourceX, sourceY) = SourceCoordinate(source, edge, x, y);
                var sourceIndex = ((sourceY * source.Width) + sourceX) * 4;
                var destinationIndex = ((y * width) + x) * 4;
                source.Pixels.AsSpan(sourceIndex, 4).CopyTo(pixels.AsSpan(destinationIndex, 4));
            }
        }

        Array.Clear(source.Pixels);
        return new PremultipliedVisual(pixels, width, height);
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
