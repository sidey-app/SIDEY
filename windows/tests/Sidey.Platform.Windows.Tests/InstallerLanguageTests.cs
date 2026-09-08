using System.Text.RegularExpressions;
using Sidey.Installer;

namespace Sidey.Platform.Windows.Tests;

public sealed class InstallerLanguageTests
{
    [Theory]
    [InlineData(1033, 1033)]
    [InlineData(2057, 1033)]
    [InlineData(3081, 1033)]
    [InlineData(1041, 1041)]
    [InlineData(1042, 1042)]
    [InlineData(1049, 1049)]
    [InlineData(1058, 1058)]
    [InlineData(2052, 2052)]
    [InlineData(4100, 2052)]
    [InlineData(1028, 1028)]
    [InlineData(3076, 1028)]
    [InlineData(5124, 1028)]
    [InlineData(0x7c04, 1028)]
    [InlineData(1036, 0)]
    public void WindowsDisplayLanguageMapsToTheSupportedLanguage(int systemLanguage, int expected)
    {
        Assert.Equal(expected, InstallerLanguages.MatchSystemLanguage(systemLanguage));
    }

    [Theory]
    [InlineData(1033)]
    [InlineData(1041)]
    [InlineData(1042)]
    [InlineData(1049)]
    [InlineData(1058)]
    [InlineData(2052)]
    [InlineData(1028)]
    public void SystemLanguageIsFirstAndTheRestAreAlphabeticalWithoutDuplicates(int systemLanguage)
    {
        InstallerLanguage[] ordered = InstallerLanguages.Ordered(systemLanguage);
        Assert.Equal(systemLanguage, ordered[0].Id);
        Assert.Equal(7, ordered.Length);
        Assert.Equal(7, ordered.Select(language => language.Id).Distinct().Count());
        string[] remaining = ordered.Skip(1).Select(language => language.EnglishName).ToArray();
        Assert.Equal(remaining.Order(StringComparer.Ordinal), remaining);
    }

    [Fact]
    public void UnsupportedDisplayLanguageUsesEnglishAndAnAlphabeticalList()
    {
        Assert.Equal(1033, InstallerLanguages.DefaultSelection(1036, 0));
        Assert.Equal(
            ["Chinese (Simplified)", "Chinese (Traditional)", "English", "Japanese", "Korean", "Russian", "Ukrainian"],
            InstallerLanguages.Ordered(1036).Select(language => language.EnglishName));
    }

    [Fact]
    public void SavedChoiceDoesNotChangeSystemFirstOrdering()
    {
        Assert.Equal(1058, InstallerLanguages.DefaultSelection(1042, 1058));
        Assert.Equal(1042, InstallerLanguages.Ordered(1042)[0].Id);
        Assert.Equal(1042, InstallerLanguages.DefaultSelection(1042, -1));
        Assert.Equal(1042, InstallerLanguages.DefaultSelection(1042, 1036));
    }

    [Fact]
    public void AllInstallerLanguagesHaveEveryCustomStringAndPreserveRuntimePlaceholders()
    {
        string source = File.ReadAllText(RepositoryPath("windows", "installer", "Sidey.Setup", "Sidey.Setup.nsi"))
            + Environment.NewLine + File.ReadAllText(RepositoryPath("windows", "installer", "Sidey.Setup", "Languages.nsh"));
        var strings = Regex.Matches(source, "^LangString (\\w+) \\$\\{LANG_(\\w+)\\} \\\"(.*)\\\"\\r?$", RegexOptions.Multiline)
            .Select(match => (Key: match.Groups[1].Value, Language: match.Groups[2].Value, Value: match.Groups[3].Value))
            .ToArray();
        var english = strings.Where(value => value.Language == "ENGLISH").ToDictionary(value => value.Key, value => value.Value);
        Assert.True(english.Count >= 25);
        foreach (string language in new[] { "ENGLISH", "KOREAN", "JAPANESE", "SIMPCHINESE", "TRADCHINESE", "RUSSIAN", "UKRAINIAN" })
        {
            var localized = strings.Where(value => value.Language == language).ToDictionary(value => value.Key, value => value.Value);
            Assert.Equal(english.Keys.Order(), localized.Keys.Order());
            foreach (string key in english.Keys)
            {
                Assert.False(string.IsNullOrWhiteSpace(localized[key]));
                Assert.Equal(Placeholders(english[key]), Placeholders(localized[key]));
            }
        }
    }

    private static string[] Placeholders(string text) =>
        Regex.Matches(text, @"\$\{[A-Z_]+\}|\$[0-9]|%LOCALAPPDATA%")
            .Select(match => match.Value).Order(StringComparer.Ordinal).ToArray();

    private static string RepositoryPath(params string[] parts)
    {
        var root = new DirectoryInfo(AppContext.BaseDirectory);
        while (root is not null && !Directory.Exists(Path.Combine(root.FullName, "windows", "src")))
        {
            root = root.Parent;
        }
        Assert.NotNull(root);
        return Path.Combine([root.FullName, .. parts]);
    }
}
