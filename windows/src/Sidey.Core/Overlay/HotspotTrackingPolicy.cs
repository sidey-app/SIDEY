namespace Sidey.Core.Overlay;

public static class HotspotTrackingPolicy
{
    public const double MinimumMovementDip = 1d;
    public static readonly TimeSpan MinimumUpdateInterval = TimeSpan.FromSeconds(1d / 15d);

    public static bool ShouldUpdate(
        PointD previousCenter,
        PointD requestedCenter,
        TimeSpan elapsed)
    {
        if (elapsed < MinimumUpdateInterval || !requestedCenter.IsFinite)
        {
            return false;
        }

        return Math.Abs(requestedCenter.X - previousCenter.X) >= MinimumMovementDip
            || Math.Abs(requestedCenter.Y - previousCenter.Y) >= MinimumMovementDip;
    }
}
