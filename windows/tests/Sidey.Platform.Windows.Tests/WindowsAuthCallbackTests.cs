using Sidey.Platform.Windows;

namespace Sidey.Platform.Windows.Tests;

public sealed class WindowsAuthCallbackTests
{
    [Theory]
    [InlineData("sidey://auth/google?error=access_denied&error_code=otp_expired", true)]
    [InlineData("sidey://auth/google#error=access_denied&error_description=cancelled", true)]
    [InlineData("sidey://auth/google?error=server_error&error_code=identity_already_exists&error_description=Identity%20is%20already%20linked#error=server_error&error_code=identity_already_exists&error_description=Identity%20is%20already%20linked&sb=", true)]
    [InlineData("sidey-dev://auth/google?error=access_denied", false)]
    [InlineData("sidey://auth/google?code=abc&error=access_denied", false)]
    [InlineData("sidey://auth/google?error=access_denied#error=server_error&sb=", false)]
    [InlineData("sidey://auth/google?error=access_denied&error_code=otp_expired#error=access_denied&sb=", false)]
    [InlineData("sidey://auth/google?error=access_denied#unexpected=value&sb=", false)]
    [InlineData("sidey://auth/google?error=access_denied#error=access_denied&sb=&sb=", false)]
    [InlineData("sidey://evil/google?error=access_denied", false)]
    public void OAuthErrorsUseOnlyTheExactCallbackAndKnownErrorFields(string uri, bool expected)
    {
        Assert.Equal(expected, WindowsAuthCallback.IsErrorCallback(uri, WindowsAuthCallback.ProductionScheme));
    }

    [Fact]
    public void SupabaseErrorCallbackReturnsSafeErrorCodeFromDuplicatedPayload()
    {
        bool accepted = WindowsAuthCallback.TryGetError(
            "sidey://auth/google?error=server_error&error_code=identity_already_exists#error=server_error&error_code=identity_already_exists&sb=",
            WindowsAuthCallback.ProductionScheme,
            out string? error,
            out string? errorCode);

        Assert.True(accepted);
        Assert.Equal("server_error", error);
        Assert.Equal("identity_already_exists", errorCode);
    }

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
