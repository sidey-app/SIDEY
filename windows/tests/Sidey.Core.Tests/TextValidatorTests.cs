using Sidey.Core.Domain;

namespace Sidey.Core.Tests;

public sealed class TextValidatorTests
{
    [Fact]
    public void NicknameUsesVisibleTextElementsInsteadOfUtf16Length()
    {
        Assert.True(ProfileValidator.IsValidNickname("햄🐹"));
        Assert.True(ProfileValidator.IsValidNickname("친구👨‍👩‍👧‍👦"));
        Assert.False(ProfileValidator.IsValidNickname("한"));
        Assert.False(ProfileValidator.IsValidNickname("123456789"));
        Assert.False(ProfileValidator.IsValidNickname("친구\n이름"));
        Assert.False(ProfileValidator.IsValidNickname("친구\t이름"));
    }

    [Fact]
    public void NicknameDraftRemovesNewlinesAndCapsAtEightTextElements()
    {
        Assert.Equal("12345678", ProfileValidator.LimitNicknameDraft("1234\n5678\t9"));
        Assert.Equal("친구", ProfileValidator.DisplayNickname("  친구  "));
    }

    [Fact]
    public void MessageNormalizationAndLimitsMatchMacBehavior()
    {
        Assert.Equal("안녕\n친구", MessageValidator.Normalize("  안녕\r\n친구  \r"));
        Assert.True(MessageValidator.IsValid("1\n2\n3"));
        Assert.False(MessageValidator.IsValid("1\n2\n3\n4"));
        Assert.True(MessageValidator.IsValid(new string('가', 200)));
        Assert.False(MessageValidator.IsValid(new string('가', 201)));
        Assert.False(MessageValidator.IsValid(string.Empty));
    }
}
