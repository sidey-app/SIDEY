using System.Text.Json;
using Sidey.Core.Localization;

namespace Sidey.Core.Tests;

public sealed class I18nTests
{
    [Fact]
    public void LoadsNestedKoreanCatalogByDottedKey()
    {
        Assert.Equal("친구들이 화면 곁에 도착했습니다.", I18n.Get("onboarding.tagline"));
    }

    [Theory]
    [InlineData("ko", "ko-KR")]
    [InlineData("en-GB", "en-US")]
    [InlineData("ja", "ja-JP")]
    [InlineData("zh-Hans-SG", "zh-CN")]
    [InlineData("zh-HK", "zh-TW")]
    [InlineData("zh-Hant", "zh-TW")]
    [InlineData("uk", "uk-UA")]
    [InlineData("ru-KZ", "ru-RU")]
    [InlineData("fr-FR", "ko-KR")]
    public void NormalizesSystemUiLanguageToASupportedCatalog(string requested, string expected)
    {
        Assert.Equal(expected, I18n.NormalizeLanguage(requested));
    }

    [Fact]
    public void SupportedCatalogOrderMatchesTheLanguagePicker()
    {
        Assert.Equal(
            ["ko-KR", "en-US", "ja-JP", "zh-CN", "zh-TW", "uk-UA", "ru-RU"],
            I18n.SupportedLanguages);
    }

    [Fact]
    public void FormatsCatalogValuesAndReturnsMissingKeysSafely()
    {
        Assert.Equal("최근 메시지 · 테스트", I18n.Format("history.roomTitle", "테스트"));
        Assert.Equal("missing.example", I18n.Get("missing.example"));
    }

    [Fact]
    public void KoreanAndEnglishHistoryCopyUseThreeDays()
    {
        Assert.Equal("메시지는 서버에서 3일 후 자동 삭제됩니다.", I18n.Get("history.retentionNotice"));
        Assert.Equal("최근 3일 기록을 모두 봤어요", I18n.Get("history.exhausted"));

        using var english = JsonDocument.Parse(File.ReadAllText(
            Path.Combine(AppContext.BaseDirectory, "Langs", "en-US.json")));
        JsonElement history = english.RootElement.GetProperty("history");
        Assert.Equal(
            "Messages are automatically deleted from the server after 3 days.",
            history.GetProperty("retentionNotice").GetString());
        Assert.Equal(
            "You’ve reached the end of the last 3 days",
            history.GetProperty("exhausted").GetString());
    }
}
