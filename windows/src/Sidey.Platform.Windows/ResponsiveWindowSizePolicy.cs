namespace Sidey.Platform.Windows;

public enum SideyWindowKind
{
    Settings,
    History,
    Onboarding,
}

public readonly record struct ResponsiveWindowSize(int Width, int Height);

public static class ResponsiveWindowSizePolicy
{
    public static ResponsiveWindowSize Minimum(
        WindowsMonitorInfo monitor,
        SideyWindowKind kind)
    {
        ArgumentNullException.ThrowIfNull(monitor);
        var scale = Math.Max(1d, monitor.Dpi / 96d);
        var specification = Specification(kind);
        return new ResponsiveWindowSize(
            Math.Min(
                Math.Max(1, (int)Math.Floor(monitor.WorkAreaPixels.Width * 0.94)),
                (int)Math.Round(specification.MinimumWidthDips * scale, MidpointRounding.AwayFromZero)),
            Math.Min(
                Math.Max(1, (int)Math.Floor(monitor.WorkAreaPixels.Height * 0.94)),
                (int)Math.Round(specification.MinimumHeightDips * scale, MidpointRounding.AwayFromZero)));
    }

    public static ResponsiveWindowSize Calculate(
        WindowsMonitorInfo monitor,
        SideyWindowKind kind)
    {
        ArgumentNullException.ThrowIfNull(monitor);
        var scale = Math.Max(1d, monitor.Dpi / 96d);
        var specification = Specification(kind);

        return new ResponsiveWindowSize(
            CalculateDimension(
                monitor.WorkAreaPixels.Width,
                specification.WidthFraction,
                specification.MinimumWidthDips,
                specification.MaximumWidthDips,
                scale),
            CalculateDimension(
                monitor.WorkAreaPixels.Height,
                specification.HeightFraction,
                specification.MinimumHeightDips,
                specification.MaximumHeightDips,
                scale));
    }

    private static int CalculateDimension(
        int availablePixels,
        double fraction,
        int minimumDips,
        int maximumDips,
        double scale)
    {
        var workAreaMaximum = Math.Max(1, (int)Math.Floor(availablePixels * 0.94));
        var maximum = Math.Min(
            workAreaMaximum,
            (int)Math.Round(maximumDips * scale, MidpointRounding.AwayFromZero));
        var minimum = Math.Min(
            maximum,
            (int)Math.Round(minimumDips * scale, MidpointRounding.AwayFromZero));
        var desired = (int)Math.Round(availablePixels * fraction, MidpointRounding.AwayFromZero);
        return Math.Clamp(desired, minimum, maximum);
    }

    private static WindowSizeSpecification Specification(SideyWindowKind kind) => kind switch
    {
        SideyWindowKind.Settings => new WindowSizeSpecification(
            WidthFraction: 0.50,
            HeightFraction: 0.60,
            MinimumWidthDips: 640,
            MinimumHeightDips: 560,
            MaximumWidthDips: 1120,
            MaximumHeightDips: 900),
        SideyWindowKind.History => new WindowSizeSpecification(
            WidthFraction: 0.30,
            HeightFraction: 0.50,
            MinimumWidthDips: 420,
            MinimumHeightDips: 400,
            MaximumWidthDips: 680,
            MaximumHeightDips: 760),
        SideyWindowKind.Onboarding => new WindowSizeSpecification(
            WidthFraction: 0.62,
            HeightFraction: 0.78,
            MinimumWidthDips: 760,
            MinimumHeightDips: 600,
            MaximumWidthDips: 1040,
            MaximumHeightDips: 800),
        _ => throw new ArgumentOutOfRangeException(nameof(kind)),
    };

    private sealed record WindowSizeSpecification(
        double WidthFraction,
        double HeightFraction,
        int MinimumWidthDips,
        int MinimumHeightDips,
        int MaximumWidthDips,
        int MaximumHeightDips);
}
