using Sidey.Platform.Windows;

namespace Sidey.Platform.Windows.Tests;

public sealed class WindowsAuthCallbackTests
{
    [Fact]
    public void DevelopmentCallbackAcceptsOnlyTheExactGoogleRouteAndOneCode()
    {
        bool accepted = WindowsAuthCallback.TryGetCode(
            "sidey-dev://auth/google?code=abc%2D123",
            WindowsAuthCallback.DevelopmentScheme,
            out Uri? callback,
            out string? code);

        Assert.True(accepted);
        Assert.Equal("sidey-dev", callback?.Scheme);
        Assert.Equal("abc-123", code);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("https://auth/google?code=abc")]
    [InlineData("sidey://auth/google?code=abc")]
    [InlineData("sidey-dev://evil/google?code=abc")]
    [InlineData("sidey-dev://auth/other?code=abc")]
    [InlineData("sidey-dev://auth/google")]
    [InlineData("sidey-dev://auth/google?code=")]
    [InlineData("sidey-dev://auth/google?code=abc&state=extra")]
    [InlineData("sidey-dev://auth/google?code=abc#fragment")]
    public void DevelopmentCallbackRejectsUnexpectedShapes(string? activationArgument)
    {
        Assert.False(WindowsAuthCallback.TryGetCode(
            activationArgument,
            WindowsAuthCallback.DevelopmentScheme,
            out _,
            out _));
    }
}
