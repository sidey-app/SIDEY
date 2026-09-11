using Sidey.Core.Domain;

namespace Sidey.Core.Overlay;

public static class CannonEmitterLayout
{
    // The emitter is authored pointing right, then rotated onto the selected edge.
    // In Windows screen coordinates that points down on the left edge and up on the right.
    public static bool ShouldMirror(double actorTangent, double targetTangent, OverlayEdge edge) => edge switch
    {
        OverlayEdge.Bottom or OverlayEdge.Left => targetTangent < actorTangent,
        OverlayEdge.Top or OverlayEdge.Right => targetTangent > actorTangent,
        _ => throw new ArgumentOutOfRangeException(nameof(edge)),
    };

    public static (double X, double Y) Center(
        (double X, double Y) actorCenter, bool mirrored, OverlayEdge edge, double scale)
    {
        double tangent = (mirrored ? -6d : 6d) * scale;
        double outward = scale; // macOS normal offset is -1 point (towards the floor).
        return edge switch
        {
            OverlayEdge.Bottom => (actorCenter.X + tangent, actorCenter.Y + outward),
            OverlayEdge.Top => (actorCenter.X - tangent, actorCenter.Y - outward),
            OverlayEdge.Left => (actorCenter.X - outward, actorCenter.Y + tangent),
            OverlayEdge.Right => (actorCenter.X + outward, actorCenter.Y - tangent),
            _ => throw new ArgumentOutOfRangeException(nameof(edge)),
        };
    }
}
