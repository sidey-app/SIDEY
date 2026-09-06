using System.Text.Json;
using Sidey.Core.Localization;

namespace Sidey.Core.Tests;

public sealed class I18nTests
{
    [Fact]
    public void LoadsNestedKoreanCatalogByDottedKey()
    {
        Assert.Equal("친구들이 화면 곁에 함께합니다.", I18n.Get("onboarding.tagline"));
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

        using JsonDocument english = JsonDocument.Parse(File.ReadAllText(
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
