using Sidey.Core.Domain;

namespace Sidey.Platform.Windows;

public static class WindowsOverlayRegionLayout
{
    private const double PreferredDepthDip = 240d;
    private const double MaximumRenderDepthDip = 360d;
    private const double MaximumTangentPaddingDip = 144d;

    public static NativePixelRect Frame(
        NativePixelRect workAreaPixels,
        uint dpi,
        OverlayRegionPreference preference)
        => Frames(workAreaPixels, dpi, preference).ActivityFrame;

    public static WindowsOverlayRegionFrames Frames(
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
        var maximumRenderDepth = Math.Max(1, Round(MaximumRenderDepthDip * dpi / 96d));
        var maximumPadding = Math.Max(0, Round(MaximumTangentPaddingDip * dpi / 96d));
        if (preference.Edge is OverlayEdge.Bottom or OverlayEdge.Top)
        {
            var length = Math.Max(1, Round(workAreaPixels.Width * preference.Span.Fraction()));
            var activity = new NativePixelRect(
                workAreaPixels.X + ((workAreaPixels.Width - length) / 2),
                preference.Edge == OverlayEdge.Top
                    ? workAreaPixels.Y
                    : workAreaPixels.Y + workAreaPixels.Height - depth,
                length,
                depth);
            var padding = Math.Min(
                maximumPadding,
                Math.Min(
                    activity.X - workAreaPixels.X,
                    workAreaPixels.X + workAreaPixels.Width - activity.X - activity.Width));
            var renderDepth = Math.Min(maximumRenderDepth, workAreaPixels.Height);
            var render = new NativePixelRect(
                activity.X - padding,
                preference.Edge == OverlayEdge.Top
                    ? workAreaPixels.Y
                    : workAreaPixels.Y + workAreaPixels.Height - renderDepth,
                activity.Width + (padding * 2),
                renderDepth);
            return new WindowsOverlayRegionFrames(activity, render);
        }

        var verticalLength = Math.Max(1, Round(workAreaPixels.Height * preference.Span.Fraction()));
        var verticalActivity = new NativePixelRect(
            preference.Edge == OverlayEdge.Left
                ? workAreaPixels.X
                : workAreaPixels.X + workAreaPixels.Width - depth,
            workAreaPixels.Y + ((workAreaPixels.Height - verticalLength) / 2),
            depth,
            verticalLength);
        var verticalPadding = Math.Min(
            maximumPadding,
            Math.Min(
                verticalActivity.Y - workAreaPixels.Y,
                workAreaPixels.Y + workAreaPixels.Height - verticalActivity.Y - verticalActivity.Height));
        var horizontalRenderDepth = Math.Min(maximumRenderDepth, workAreaPixels.Width);
        var verticalRender = new NativePixelRect(
            preference.Edge == OverlayEdge.Left
                ? workAreaPixels.X
                : workAreaPixels.X + workAreaPixels.Width - horizontalRenderDepth,
            verticalActivity.Y - verticalPadding,
            horizontalRenderDepth,
            verticalActivity.Height + (verticalPadding * 2));
        return new WindowsOverlayRegionFrames(verticalActivity, verticalRender);
    }

    private static int Round(double value) =>
        (int)Math.Round(value, MidpointRounding.AwayFromZero);
}

public sealed record WindowsOverlayRegionFrames(
    NativePixelRect ActivityFrame,
    NativePixelRect RenderFrame);
