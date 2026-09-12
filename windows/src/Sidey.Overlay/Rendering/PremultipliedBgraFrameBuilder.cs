using Sidey.Core.Domain;

namespace Sidey.Overlay.Rendering;

internal static class PremultipliedBgraFrameBuilder
{
    private const int BytesPerPixel = 4;

    internal static byte[] BuildFrame(
        ReadOnlySpan<byte> sheet,
        PixelCharacterDefinition definition,
        int frame,
        int scale,
        bool flipHorizontally,
        OverlayEdge edge)
    {
        ArgumentNullException.ThrowIfNull(definition);
        int sheetWidth = checked(definition.FrameWidth * definition.FrameCount);
        int expectedLength = checked(
            sheetWidth * definition.FrameHeight * BytesPerPixel);
        if (sheet.Length != expectedLength)
        {
            throw new ArgumentException(
                $"The BGRA sheet dimensions do not match {definition.Id}.",
                nameof(sheet));
        }

        if (frame < 0 || frame >= definition.FrameCount)
        {
            throw new ArgumentOutOfRangeException(nameof(frame));
        }

        if (scale <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(scale));
        }

        if (definition.FrameWidth != definition.FrameHeight)
        {
            throw new InvalidDataException("SIDEY rotation requires square character frames.");
        }

        int authoredSize = definition.FrameWidth;
        int outputSize = checked(authoredSize * scale);
        byte[] output = new byte[checked(outputSize * outputSize * BytesPerPixel)];
        for (int outputY = 0; outputY < outputSize; outputY++)
        {
            for (int outputX = 0; outputX < outputSize; outputX++)
            {
                int rotatedX = outputX / scale;
                int rotatedY = outputY / scale;
                (int localSourceX, int sourceY) = InverseRotate(
                    rotatedX,
                    rotatedY,
                    authoredSize,
                    edge);
                if (flipHorizontally)
                {
                    localSourceX = authoredSize - 1 - localSourceX;
                }

                int sourceX = (frame * authoredSize) + localSourceX;
                int sourceIndex = ((sourceY * sheetWidth) + sourceX) * BytesPerPixel;
                int outputIndex = ((outputY * outputSize) + outputX) * BytesPerPixel;
                byte alpha = sheet[sourceIndex + 3];
                output[outputIndex] = Premultiply(sheet[sourceIndex], alpha);
                output[outputIndex + 1] = Premultiply(sheet[sourceIndex + 1], alpha);
                output[outputIndex + 2] = Premultiply(sheet[sourceIndex + 2], alpha);
                output[outputIndex + 3] = alpha;
            }
        }

        return output;
    }

    private static byte Premultiply(byte color, byte alpha) =>
        (byte)(((color * alpha) + 127) / 255);

    private static (int X, int Y) InverseRotate(
        int x,
        int y,
        int size,
        OverlayEdge edge) => edge switch
        {
            OverlayEdge.Bottom => (x, y),
            OverlayEdge.Top => (size - 1 - x, size - 1 - y),
            OverlayEdge.Left => (y, size - 1 - x),
            OverlayEdge.Right => (size - 1 - y, x),
            _ => throw new ArgumentOutOfRangeException(nameof(edge)),
        };
}
