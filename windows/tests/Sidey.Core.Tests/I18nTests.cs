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
}
