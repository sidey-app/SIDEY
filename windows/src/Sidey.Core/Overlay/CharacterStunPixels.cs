namespace Sidey.Core.Overlay;

public readonly record struct StunPixel(int X, int Y, bool IsStar, bool IsOutline = false);

/// <summary>24-pixel character coordinates; usable by both the native overlay and preview.</summary>
public static class CharacterStunPixels
{
    private static readonly string[] s_star = ["...o...", "..oyo..", "ooyyyoo", "oyyyyyo", ".oyyyo.", ".oyoyo.", ".o...o."];
    private static readonly StunPixel[][] s_frames = [.. Enumerable.Range(0, 36).Select(i => Generate(i / 30d).ToArray())];
    public static int MaximumPixelCount { get; } = s_frames.Max(frame => frame.Length);
    public static IReadOnlyList<StunPixel> Create(double elapsed, bool animated) => s_frames[animated ? (int)(Math.Max(0, elapsed) * 30) % s_frames.Length : 0];

    private static IEnumerable<StunPixel> Generate(double elapsed)
    {
        double phase = elapsed / 1.2 * Math.PI * 2;
        var ring = new HashSet<(int X, int Y)>();
        for (int i = 0; i < 48; i++)
        {
            double angle = i * Math.PI / 24;
            var point = ((int)Math.Round(12 + Math.Cos(angle) * 8), (int)Math.Round(6 + Math.Sin(angle) * 3));
            if (ring.Add(point))
                yield return new StunPixel(point.Item1, point.Item2, false);
        }
        for (int i = 0; i < 3; i++)
        {
            double angle = phase + i * Math.PI * 2 / 3;
            int x = (int)Math.Round(12 + Math.Cos(angle) * 8);
            int y = (int)Math.Round(6 + Math.Sin(angle) * 3);
            for (int row = 0; row < s_star.Length; row++)
                for (int column = 0; column < s_star[row].Length; column++)
                    if (s_star[row][column] is var color && color != '.')
                        yield return new StunPixel(x + column - 3, y + row - 3, true, color == 'o');
        }
    }
}
