using Sidey.Core.Domain;

namespace Sidey.Core.Tests;

public sealed class GlobalShortcutTests
{
    private const GlobalShortcutModifiers ControlShift = GlobalShortcutModifiers.Control | GlobalShortcutModifiers.Shift;
    private const GlobalShortcutModifiers AltShift = GlobalShortcutModifiers.Alt | GlobalShortcutModifiers.Shift;
    private const int KeyM = 0x4D;

    [Theory]
    [InlineData(ControlShift, KeyM, GlobalShortcutValidation.Valid)]
    [InlineData(AltShift, 0x37, GlobalShortcutValidation.Valid)]
    [InlineData(ControlShift, 0x20, GlobalShortcutValidation.Valid)]
    [InlineData(AltShift, 0x70, GlobalShortcutValidation.Valid)]
    [InlineData(AltShift, 0x7A, GlobalShortcutValidation.Valid)]
    [InlineData(ControlShift, 0x7B, GlobalShortcutValidation.UnsupportedKey)]
    [InlineData(ControlShift, 0x09, GlobalShortcutValidation.UnsupportedKey)]
    [InlineData(ControlShift, 0x61, GlobalShortcutValidation.UnsupportedKey)]
    [InlineData(GlobalShortcutModifiers.Control, KeyM, GlobalShortcutValidation.TooFewModifiers)]
    [InlineData(GlobalShortcutModifiers.Shift, 0x20, GlobalShortcutValidation.TooFewModifiers)]
    [InlineData(GlobalShortcutModifiers.None, KeyM, GlobalShortcutValidation.TooFewModifiers)]
    [InlineData(GlobalShortcutModifiers.Control | GlobalShortcutModifiers.Alt, KeyM, GlobalShortcutValidation.UsesControlAlt)]
    [InlineData(ControlShift | GlobalShortcutModifiers.Alt, KeyM, GlobalShortcutValidation.UsesControlAlt)]
    [InlineData(GlobalShortcutModifiers.Windows | GlobalShortcutModifiers.Shift, KeyM, GlobalShortcutValidation.UsesWindowsKey)]
    [InlineData((GlobalShortcutModifiers)16 | ControlShift, KeyM, GlobalShortcutValidation.UnsupportedKey)]
    public void ValidationKeepsOnlyCombinationsThatDoNotCollideWithTyping(
        GlobalShortcutModifiers modifiers,
        int keyCode,
        GlobalShortcutValidation expected)
    {
        Assert.Equal(expected, new GlobalShortcut(modifiers, keyCode).Validate());
    }

    [Theory]
    [InlineData(ControlShift, KeyM, "Ctrl+Shift+M")]
    [InlineData(AltShift, 0x37, "Alt+Shift+7")]
    [InlineData(ControlShift, 0x20, "Ctrl+Shift+Space")]
    [InlineData(AltShift, 0x74, "Alt+Shift+F5")]
    public void FormattingUsesStableLanguageIndependentText(
        GlobalShortcutModifiers modifiers,
        int keyCode,
        string expected)
    {
        Assert.Equal(expected, new GlobalShortcut(modifiers, keyCode).ToString());
    }

    [Theory]
    [InlineData("Ctrl+Shift+M", ControlShift, KeyM)]
    [InlineData("shift + control + m", ControlShift, KeyM)]
    [InlineData("Alt+Shift+space", AltShift, 0x20)]
    [InlineData("ALT+SHIFT+f11", AltShift, 0x7A)]
    public void ParsingAcceptsSavedAndHandEditedText(string text, GlobalShortcutModifiers modifiers, int keyCode)
    {
        Assert.True(GlobalShortcut.TryParse(text, out GlobalShortcut shortcut));
        Assert.Equal(new GlobalShortcut(modifiers, keyCode), shortcut);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("Ctrl+Shift")]
    [InlineData("Ctrl+Ctrl+M")]
    [InlineData("Ctrl++M")]
    [InlineData("Hyper+Shift+M")]
    [InlineData("Ctrl+Shift+MM")]
    [InlineData("Ctrl+Shift+F0")]
    [InlineData("Ctrl+Shift+F01")]
    [InlineData("Ctrl+Shift+F12")]
    [InlineData("Ctrl+Shift+0x4D")]
    public void ParsingRejectsMalformedOrUnsupportedText(string? text)
    {
        Assert.False(GlobalShortcut.TryParse(text, out _));
    }

    [Fact]
    public void EverySupportedKeyRoundTripsThroughSavedText()
    {
        for (int keyCode = 0; keyCode <= 0xFF; keyCode++)
        {
            var shortcut = new GlobalShortcut(ControlShift, keyCode);

            bool roundTrips = GlobalShortcut.TryParse(shortcut.ToString(), out GlobalShortcut parsed)
                && parsed == shortcut;

            Assert.Equal(GlobalShortcut.IsSupportedKey(keyCode), roundTrips);
        }
    }

    [Fact]
    public void PreferencesStartEmptyAndReplaceOnlyTheRequestedAction()
    {
        var compose = new GlobalShortcut(ControlShift, KeyM);
        var overlay = new GlobalShortcut(AltShift, 0x4F);

        GlobalShortcutPreferences preferences = GlobalShortcutPreferences.Empty
            .With(GlobalShortcutAction.Compose, compose)
            .With(GlobalShortcutAction.ToggleOverlay, overlay)
            .With(GlobalShortcutAction.ToggleOverlay, null);

        Assert.Equal(
            [GlobalShortcutAction.Compose, GlobalShortcutAction.ToggleOverlay, GlobalShortcutAction.ToggleQuietMode],
            GlobalShortcutPreferences.Actions);
        Assert.Equal("Ctrl+Shift+M", preferences.Compose);
        Assert.Null(preferences.ToggleOverlay);
        Assert.Null(preferences.ToggleQuietMode);
        Assert.Equal(compose, preferences.Get(GlobalShortcutAction.Compose));
        Assert.Equal(GlobalShortcutAction.Compose, preferences.FindAction(compose));
        Assert.Null(preferences.FindAction(overlay));
    }

    [Fact]
    public void NormalizationDropsUnusableTextAndRepeatedCombinations()
    {
        var preferences = new GlobalShortcutPreferences
        {
            Compose = "shift+ctrl+m",
            ToggleOverlay = "Ctrl+Shift+M",
            ToggleQuietMode = "Ctrl+Alt+Q",
        };

        GlobalShortcutPreferences normalized = preferences.Normalize();

        Assert.Equal("Ctrl+Shift+M", normalized.Compose);
        Assert.Null(normalized.ToggleOverlay);
        Assert.Null(normalized.ToggleQuietMode);
        Assert.Null(preferences.Get(GlobalShortcutAction.ToggleQuietMode));
    }
}
