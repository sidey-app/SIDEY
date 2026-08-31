using Sidey.Core.Domain;

namespace Sidey.Platform.Windows;

public static class WindowsOverlayRegionLayout
{
    private const double PreferredDepthDip = 240d;

    public static NativePixelRect Frame(
        NativePixelRect workAreaPixels,
        uint dpi,
        OverlayRegionPreference preference)
    {
        if (!workAreaPixels.IsValid)
        {
            throw new ArgumentOutOfRangeException(nameof(workAreaPixels));
        }

        if (dpi == 0)
        {
            throw new ArgumentOutOfRangeException(nameof(dpi));
        }

        var preferredDepth = Round(PreferredDepthDip * dpi / 96d);
        var depth = Math.Max(1, Math.Min(preferredDepth, workAreaPixels.Height / 3));
        if (preference.Edge is OverlayEdge.Bottom or OverlayEdge.Top)
        {
            var length = Math.Max(1, Round(workAreaPixels.Width * preference.Span.Fraction()));
            return new NativePixelRect(
                workAreaPixels.X + ((workAreaPixels.Width - length) / 2),
                preference.Edge == OverlayEdge.Top
                    ? workAreaPixels.Y
                    : workAreaPixels.Y + workAreaPixels.Height - depth,
                length,
                depth);
        }

        var verticalLength = Math.Max(1, Round(workAreaPixels.Height * preference.Span.Fraction()));
        return new NativePixelRect(
            preference.Edge == OverlayEdge.Left
                ? workAreaPixels.X
                : workAreaPixels.X + workAreaPixels.Width - depth,
            workAreaPixels.Y + ((workAreaPixels.Height - verticalLength) / 2),
            depth,
            verticalLength);
    }

    private static int Round(double value) =>
        (int)Math.Round(value, MidpointRounding.AwayFromZero);
}
