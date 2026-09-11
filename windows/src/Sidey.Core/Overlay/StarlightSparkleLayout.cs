using Sidey.Core.Domain;

namespace Sidey.Core.Overlay;

public static class StarlightSparkleLayout
{
    // macOS places ambient particles in character-center local coordinates,
    // not foot coordinates. Positive normal points inward/above the character.
    public static (double X, double Y) Point(
        (double X, double Y) center, double tangent, double normal, OverlayEdge edge) => edge switch
        {
            OverlayEdge.Bottom => (center.X + tangent, center.Y - normal),
            OverlayEdge.Top => (center.X - tangent, center.Y + normal),
            OverlayEdge.Left => (center.X + normal, center.Y + tangent),
            OverlayEdge.Right => (center.X - normal, center.Y - tangent),
            _ => throw new ArgumentOutOfRangeException(nameof(edge)),
        };

    public static (double Tangent, double Normal, double Radius, double Opacity) Ambient(
        double elapsed, int index, int seed)
    {
        int cycle = (int)Math.Floor(elapsed / 1.2d);
        double progress = (elapsed % 1.2d) / 1.05d;
        if (progress < 0 || progress > 1)
            return (0, 0, 0, 0);
        int burstSeed = seed ^ (cycle * 7919) ^ ((index + 1) * 1543);
        double envelope = 1 - Math.Abs((2 * progress) - 1);
        return (
            -25 + (50 * Unit(burstSeed)),
            5 + (32 * Unit(burstSeed ^ 0x51A7)) + (4 * progress),
            (2.6 + (1.4 * Unit(burstSeed ^ 0x3571))) * (0.32 + (0.68 * envelope)),
            envelope);
    }

    public static double Unit(int value)
    {
        uint mixed = unchecked((uint)value);
        unchecked
        {
            mixed ^= mixed >> 16;
            mixed *= 0x7FEB352D;
            mixed ^= mixed >> 15;
            mixed *= 0x846CA68B;
            mixed ^= mixed >> 16;
        }
        return mixed / (double)uint.MaxValue;
    }
}
