using System.Globalization;
using System.Numerics;
using System.Text;

namespace Sidey.Core.Domain;

[Flags]
public enum GlobalShortcutModifiers
{
    None = 0,
    Control = 1,
    Alt = 2,
    Shift = 4,
    Windows = 8,
}

public enum GlobalShortcutValidation
{
    Valid = 0,
    UnsupportedKey = 1,
    UsesWindowsKey = 2,
    UsesControlAlt = 3,
    TooFewModifiers = 4,
}

/// <summary>
/// A system-wide key combination chosen by the user. <see cref="KeyCode"/> is a
/// Windows virtual-key code so the settings view and the native registrar share it.
/// </summary>
public readonly record struct GlobalShortcut(GlobalShortcutModifiers Modifiers, int KeyCode)
{
    private const int SpaceKeyCode = 0x20;
    private const int DigitZeroKeyCode = 0x30;
    private const int DigitNineKeyCode = 0x39;
    private const int LetterAKeyCode = 0x41;
    private const int LetterZKeyCode = 0x5A;
    private const int FunctionOneKeyCode = 0x70;

    // F12 stays out because Windows reserves it for attached debuggers.
    private const int FunctionElevenKeyCode = 0x7A;

    private const GlobalShortcutModifiers KnownModifiers = GlobalShortcutModifiers.Control
        | GlobalShortcutModifiers.Alt
        | GlobalShortcutModifiers.Shift
        | GlobalShortcutModifiers.Windows;

    public static bool IsSupportedKey(int keyCode) => keyCode is SpaceKeyCode
        or (>= DigitZeroKeyCode and <= DigitNineKeyCode)
        or (>= LetterAKeyCode and <= LetterZKeyCode)
        or (>= FunctionOneKeyCode and <= FunctionElevenKeyCode);

    public GlobalShortcutValidation Validate()
    {
        if (!IsSupportedKey(KeyCode) || (Modifiers & ~KnownModifiers) != 0)
        {
            return GlobalShortcutValidation.UnsupportedKey;
        }

        if (Modifiers.HasFlag(GlobalShortcutModifiers.Windows))
        {
            return GlobalShortcutValidation.UsesWindowsKey;
        }

        // Many keyboard layouts type characters with AltGr, which Windows reports as Ctrl+Alt.
        if (Modifiers.HasFlag(GlobalShortcutModifiers.Control) && Modifiers.HasFlag(GlobalShortcutModifiers.Alt))
        {
            return GlobalShortcutValidation.UsesControlAlt;
        }

        return BitOperations.PopCount((uint)Modifiers) < 2
            ? GlobalShortcutValidation.TooFewModifiers
            : GlobalShortcutValidation.Valid;
    }

    /// <summary>Formats the stable, language-independent text that is also persisted.</summary>
    public override string ToString()
    {
        var builder = new StringBuilder();
        AppendModifier(builder, GlobalShortcutModifiers.Control, "Ctrl");
        AppendModifier(builder, GlobalShortcutModifiers.Alt, "Alt");
        AppendModifier(builder, GlobalShortcutModifiers.Shift, "Shift");
        AppendModifier(builder, GlobalShortcutModifiers.Windows, "Win");
        builder.Append(KeyName(KeyCode));
        return builder.ToString();
    }

    public static bool TryParse(string? value, out GlobalShortcut shortcut)
    {
        shortcut = default;
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        string[] parts = value.Split('+', StringSplitOptions.TrimEntries);
        GlobalShortcutModifiers modifiers = GlobalShortcutModifiers.None;
        foreach (string part in parts[..^1])
        {
            GlobalShortcutModifiers modifier = part.ToUpperInvariant() switch
            {
                "CTRL" or "CONTROL" => GlobalShortcutModifiers.Control,
                "ALT" => GlobalShortcutModifiers.Alt,
                "SHIFT" => GlobalShortcutModifiers.Shift,
                "WIN" or "WINDOWS" => GlobalShortcutModifiers.Windows,
                _ => GlobalShortcutModifiers.None,
            };
            if (modifier == GlobalShortcutModifiers.None || modifiers.HasFlag(modifier))
            {
                return false;
            }

            modifiers |= modifier;
        }

        if (!TryParseKey(parts[^1], out int keyCode))
        {
            return false;
        }

        shortcut = new GlobalShortcut(modifiers, keyCode);
        return true;
    }

    private void AppendModifier(StringBuilder builder, GlobalShortcutModifiers modifier, string name)
    {
        if (Modifiers.HasFlag(modifier))
        {
            builder.Append(name).Append('+');
        }
    }

    private static string KeyName(int keyCode) => keyCode switch
    {
        SpaceKeyCode => "Space",
        >= FunctionOneKeyCode and <= FunctionElevenKeyCode =>
            string.Create(CultureInfo.InvariantCulture, $"F{keyCode - FunctionOneKeyCode + 1}"),
        (>= DigitZeroKeyCode and <= DigitNineKeyCode) or (>= LetterAKeyCode and <= LetterZKeyCode) =>
            ((char)keyCode).ToString(),
        _ => string.Create(CultureInfo.InvariantCulture, $"0x{keyCode:X2}"),
    };

    private static bool TryParseKey(string value, out int keyCode)
    {
        keyCode = 0;
        if (string.Equals(value, "Space", StringComparison.OrdinalIgnoreCase))
        {
            keyCode = SpaceKeyCode;
            return true;
        }

        if (value.Length == 1 && char.IsAsciiLetterOrDigit(value[0]))
        {
            keyCode = char.ToUpperInvariant(value[0]);
            return true;
        }

        if (value.Length is 2 or 3
            && value[0] is 'F' or 'f'
            && value[1] != '0'
            && int.TryParse(value.AsSpan(1), NumberStyles.None, CultureInfo.InvariantCulture, out int number)
            && number is >= 1 and <= 11)
        {
            keyCode = FunctionOneKeyCode + number - 1;
            return true;
        }

        return false;
    }
}
