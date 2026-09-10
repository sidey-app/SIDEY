using Sidey.Core.Domain;

namespace Sidey.Overlay;

// Match macOS: snapshot the launch point, duration and arc when the throw arrives,
// while continuing to follow the target's current character center during flight.
internal readonly record struct CharacterThrowTrajectory
{
    public (double X, double Y) Start { get; }
    public double DurationSeconds { get; }
    public double ArcHeightPixels { get; }

    public CharacterThrowTrajectory(
        (double X, double Y) start,
        (double X, double Y) end,
        double dpiScale)
    {
        Start = start;
        double distanceDip = Math.Sqrt(
            Math.Pow(end.X - start.X, 2d) + Math.Pow(end.Y - start.Y, 2d)) / dpiScale;
        DurationSeconds = Math.Clamp(0.35d + (distanceDip / 1600d), 0.35d, 0.95d);
        ArcHeightPixels = Math.Clamp(distanceDip * 0.18d, 24d, 96d) * dpiScale;
    }

    public (double X, double Y) PointAt(
        (double X, double Y) end,
        double flightElapsedSeconds,
        OverlayEdge edge)
    {
        (double, double) midpoint = ((Start.X + end.X) / 2d, (Start.Y + end.Y) / 2d);
        (double, double) control = edge switch
        {
            OverlayEdge.Bottom => (midpoint.Item1, midpoint.Item2 - ArcHeightPixels),
            OverlayEdge.Top => (midpoint.Item1, midpoint.Item2 + ArcHeightPixels),
            OverlayEdge.Left => (midpoint.Item1 + ArcHeightPixels, midpoint.Item2),
            OverlayEdge.Right => (midpoint.Item1 - ArcHeightPixels, midpoint.Item2),
            _ => throw new ArgumentOutOfRangeException(nameof(edge)),
        };
        double progress = Math.Clamp(flightElapsedSeconds / DurationSeconds, 0d, 1d);
        double inverse = 1d - progress;
        return (
            (inverse * inverse * Start.X) + (2d * inverse * progress * control.Item1) + (progress * progress * end.X),
            (inverse * inverse * Start.Y) + (2d * inverse * progress * control.Item2) + (progress * progress * end.Y));
    }
}
