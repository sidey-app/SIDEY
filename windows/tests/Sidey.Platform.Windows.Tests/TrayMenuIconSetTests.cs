using Sidey.Platform.Windows;

namespace Sidey.Platform.Windows.Tests;

public sealed class TrayMenuIconSetTests
{
    [Fact]
    public void EveryFluentGlyphCreatesANativeMenuBitmap()
    {
        using var icons = new TrayMenuIconSet(16);

        Assert.All(
            Enum.GetValues<TrayMenuIcon>(),
            icon => Assert.NotEqual(nint.Zero, icons.Get(icon)));
    }

    [Fact]
    public void EveryTrayMenuItemHasADistinctFluentGlyph()
    {
        var glyphs = Enum.GetValues<TrayMenuIcon>()
            .Select(TrayMenuIconSet.Glyph)
            .ToArray();

        Assert.All(glyphs, glyph => Assert.Single(glyph));
        Assert.Equal(glyphs.Length, glyphs.Distinct(StringComparer.Ordinal).Count());
    }

    [Fact]
    public void GlyphCoverageIsConvertedToPremultipliedMenuTextColor()
    {
        byte[] pixels = [128, 128, 128, 0, 0, 0, 0, 0];

        TrayMenuIconSet.ApplyMenuTextColor(pixels, color: 0x00332211);

        Assert.Equal([25, 17, 8, 128, 0, 0, 0, 0], pixels);
    }
}
