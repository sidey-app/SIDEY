using System.Globalization;

namespace Sidey.Core.Domain;

public static class ProfileValidator
{
    public const int MinimumNicknameCharacters = 2;
    public const int MaximumNicknameCharacters = 8;

    public static string NormalizeNickname(string value)
    {
        ArgumentNullException.ThrowIfNull(value);
        return value.Trim();
    }

    public static bool IsValidNickname(string value)
    {
        ArgumentNullException.ThrowIfNull(value);
        var normalized = NormalizeNickname(value);
        var length = TextElementCount(normalized);
        return length is >= MinimumNicknameCharacters and <= MaximumNicknameCharacters
            && !value.Any(IsNewline)
            && !value.Contains('\t');
    }

    public static string LimitNicknameDraft(string value)
    {
        ArgumentNullException.ThrowIfNull(value);
        var singleLine = new string(value.Where(character => character != '\t' && !IsNewline(character)).ToArray());
        return PrefixTextElements(singleLine, MaximumNicknameCharacters);
    }

    public static string DisplayNickname(string value) =>
        PrefixTextElements(NormalizeNickname(value), MaximumNicknameCharacters);

    internal static int TextElementCount(string value) =>
        new StringInfo(value).LengthInTextElements;

    internal static string PrefixTextElements(string value, int maximum)
    {
        var indexes = StringInfo.ParseCombiningCharacters(value);
        return indexes.Length <= maximum ? value : value[..indexes[maximum]];
    }

    private static bool IsNewline(char character) => character is
        '\n' or '\v' or '\f' or '\r' or '\u0085' or '\u2028' or '\u2029';
}

public static class MessageValidator
{
    public const int MaximumCharacters = 200;
    public const int MaximumLines = 3;

    public static string Normalize(string value)
    {
        ArgumentNullException.ThrowIfNull(value);
        return value
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n')
            .Trim();
    }

    public static bool IsValid(string value)
    {
        ArgumentNullException.ThrowIfNull(value);
        return value.Length > 0
            && ProfileValidator.TextElementCount(value) <= MaximumCharacters
            && LineCount(value) <= MaximumLines;
    }

    public static bool IsValidDraft(string value)
    {
        ArgumentNullException.ThrowIfNull(value);
        var normalizedNewlines = value
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n');
        return ProfileValidator.TextElementCount(value) <= MaximumCharacters
            && LineCount(normalizedNewlines) <= MaximumLines;
    }

    private static int LineCount(string value) => value.Count(character => character == '\n') + 1;
}
