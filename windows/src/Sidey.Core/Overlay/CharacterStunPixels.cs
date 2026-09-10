namespace Sidey.Core.Overlay;

public readonly record struct StunPixel(int X, int Y, bool IsStar, bool IsOutline = false);

/// <summary>24-pixel character coordinates; usable by both the native overlay and preview.</summary>
public static class CharacterStunPixels
{
    private static readonly string[] Star = ["...o...", "..oyo..", "ooyyyoo", "oyyyyyo", ".oyyyo.", ".oyoyo.", ".o...o."];
    private static readonly StunPixel[][] Frames = Enumerable.Range(0, 36).Select(i => Generate(i / 30d).ToArray()).ToArray();
    public static int MaximumPixelCount { get; } = Frames.Max(frame => frame.Length);
    public static IReadOnlyList<StunPixel> Create(double elapsed, bool animated) => Frames[animated ? (int)(Math.Max(0, elapsed) * 30) % Frames.Length : 0];

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
            for (int row = 0; row < Star.Length; row++)
                for (int column = 0; column < Star[row].Length; column++)
                    if (Star[row][column] is var color && color != '.')
                        yield return new StunPixel(x + column - 3, y + row - 3, true, color == 'o');
        }
    }
}
