using Sidey.Core.Domain;

namespace Sidey.Core.Overlay;

public readonly record struct PointD(double X, double Y)
{
    public bool IsFinite => double.IsFinite(X) && double.IsFinite(Y);
}

public readonly record struct RectD(double X, double Y, double Width, double Height)
{
    public double MinX => X;
    public double MidX => X + (Width / 2d);
    public double MaxX => X + Width;
    public double MinY => Y;
    public double MidY => Y + (Height / 2d);
    public double MaxY => Y + Height;

    public bool Contains(PointD point) =>
        point.X >= MinX && point.X <= MaxX && point.Y >= MinY && point.Y <= MaxY;

    public RectD Inset(double dx, double dy) =>
        new(X + dx, Y + dy, Width - (2d * dx), Height - (2d * dy));
}

public sealed record MonitorGeometry(
    string Identifier,
    string Name,
    RectD WorkAreaDip,
    uint Dpi,
    bool IsPrimary);

public static class OverlayRegionLayout
{
    public const double PreferredDepth = 240d;

    public static MonitorGeometry? SelectMonitor(
        OverlayRegionPreference preference,
        IReadOnlyList<MonitorGeometry> monitors)
    {
        if (monitors.Count == 0)
        {
            return null;
        }

        if (preference.MonitorIdentifier is { } identifier)
        {
            var selected = monitors.FirstOrDefault(monitor => monitor.Identifier == identifier);
            if (selected is not null)
            {
                return selected;
            }
        }

        return monitors.FirstOrDefault(monitor => monitor.IsPrimary) ?? monitors[0];
    }

    public static RectD Frame(OverlayRegionPreference preference, RectD workArea)
    {
        var depth = Math.Min(PreferredDepth, workArea.Height / 3d);
        if (preference.Edge is OverlayEdge.Bottom or OverlayEdge.Top)
        {
            var length = workArea.Width * preference.Span.Fraction();
            return new RectD(
                workArea.MidX - (length / 2d),
                preference.Edge == OverlayEdge.Bottom ? workArea.MinY : workArea.MaxY - depth,
                length,
                depth);
        }

        var verticalLength = workArea.Height * preference.Span.Fraction();
        return new RectD(
            preference.Edge == OverlayEdge.Left ? workArea.MinX : workArea.MaxX - depth,
            workArea.MidY - (verticalLength / 2d),
            depth,
            verticalLength);
    }
}

public static class PixelScalePolicy
{
    public static int IntegerScale(uint dpi) => Math.Max(
        2,
        (int)Math.Round(2d * dpi / 96d, MidpointRounding.AwayFromZero));
}

public sealed class EdgeTrackGeometry
{
    public const double CharacterPointSize = 48d;
    public const double HotspotPointSize = 52d;
    public const int FootBaselinePixel = 3;
    public const double FootInset = (CharacterPointSize / 2d) - (FootBaselinePixel * 2d);

    private readonly double _tangentExtent;

    public EdgeTrackGeometry(
        RectD bounds,
        OverlayEdge edge,
        double tangentExtent = HotspotPointSize)
    {
        if (!double.IsFinite(tangentExtent) || tangentExtent <= 0d)
        {
            throw new ArgumentOutOfRangeException(nameof(tangentExtent));
        }

        Bounds = bounds;
        Edge = edge;
        _tangentExtent = tangentExtent;
    }

    public RectD Bounds { get; }
    public OverlayEdge Edge { get; }
    public double TangentLength => Edge is OverlayEdge.Bottom or OverlayEdge.Top ? Bounds.Width : Bounds.Height;
    public double TrackLowerBound => Math.Min(_tangentExtent / 2d, Math.Max(0d, TangentLength / 2d));
    public double TrackUpperBound => Math.Max(TrackLowerBound, TangentLength - TrackLowerBound);

    public double Clamp(double tangent)
    {
        var finite = double.IsFinite(tangent) ? tangent : TrackLowerBound;
        return Math.Clamp(finite, TrackLowerBound, TrackUpperBound);
    }

    public PointD PointFor(double tangent)
    {
        var value = Clamp(tangent);
        return Edge switch
        {
            OverlayEdge.Bottom => new PointD(Bounds.MinX + value, Bounds.MinY + FootInset),
            OverlayEdge.Top => new PointD(Bounds.MinX + value, Bounds.MaxY - FootInset),
            OverlayEdge.Left => new PointD(Bounds.MinX + FootInset, Bounds.MinY + value),
            OverlayEdge.Right => new PointD(Bounds.MaxX - FootInset, Bounds.MinY + value),
            _ => throw new ArgumentOutOfRangeException(),
        };
    }

    public PointD FootPointFor(double tangent)
    {
        var anchor = PointFor(tangent);
        return Edge switch
        {
            OverlayEdge.Bottom => new PointD(anchor.X, anchor.Y - FootInset),
            OverlayEdge.Top => new PointD(anchor.X, anchor.Y + FootInset),
            OverlayEdge.Left => new PointD(anchor.X - FootInset, anchor.Y),
            OverlayEdge.Right => new PointD(anchor.X + FootInset, anchor.Y),
            _ => throw new ArgumentOutOfRangeException(),
        };
    }
}
