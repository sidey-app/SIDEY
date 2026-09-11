using Sidey.Core.Domain;

namespace Sidey.Core.Overlay;

public static class CharacterNameplateLayout
{
    // The 24px canvas extends 21px inward from its foot baseline; keep a 1px gap.
    public const int DistanceFromFoot = 22;

    public static (double X, double Y) Position(
        (double X, double Y) foot, double width, double height, double pixelScale, OverlayEdge edge)
    {
        double distance = DistanceFromFoot * pixelScale;
        return edge switch
        {
            OverlayEdge.Bottom => (foot.X - width / 2, foot.Y - distance - height),
            OverlayEdge.Top => (foot.X - width / 2, foot.Y + distance),
            OverlayEdge.Left => (foot.X + distance, foot.Y - height / 2),
            OverlayEdge.Right => (foot.X - distance - width, foot.Y - height / 2),
            _ => throw new ArgumentOutOfRangeException(nameof(edge)),
        };
    }
}
