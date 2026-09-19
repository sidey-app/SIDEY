using System.ComponentModel;
using System.Diagnostics;
using Sidey.Platform.Windows.Shell;

namespace Sidey.Platform.Windows.Tests;

public sealed class WindowsExternalUriLauncherTests
{
    [Fact]
    public void OAuthAddressIsHandedToTheDefaultBrowserOnceWithoutSplittingOrReencoding()
    {
        string address = "https://accounts.google.com/o/oauth2/v2/auth?client_id=test-client"
            + "&redirect_uri=https%3A%2F%2Fexample.supabase.co%2Fauth%2Fv1%2Fcallback"
            + "&response_type=code&scope=email+profile&state=" + new string('a', 4096)
            + "%2B%2F%3D&login_hint=test%2Blogin%40example.com";
        var launches = new List<ProcessStartInfo>();

        WindowsExternalUriLauncher.Open(new Uri(address), launches.Add);

        ProcessStartInfo start = Assert.Single(launches);
        Assert.Equal(address, start.FileName);
        Assert.True(start.UseShellExecute);
        Assert.Empty(start.Arguments);
        Assert.Empty(start.ArgumentList);
        Assert.Empty(start.Verb);
    }

    [Fact]
    public void SettingsProtocolContinuesToUseTheRegisteredWindowsHandler()
    {
        var launches = new List<ProcessStartInfo>();

        WindowsExternalUriLauncher.Open(new Uri("ms-settings:colors"), launches.Add);

        ProcessStartInfo start = Assert.Single(launches);
        Assert.Equal("ms-settings:colors", start.FileName);
        Assert.True(start.UseShellExecute);
        Assert.Empty(start.Arguments);
    }

    [Fact]
    public void ShellLaunchFailureReachesTheCaller()
    {
        var failure = new Win32Exception(1155);

        Win32Exception actual = Assert.Throws<Win32Exception>(() =>
            WindowsExternalUriLauncher.Open(new Uri("https://example.com/"), _ => throw failure));

        Assert.Same(failure, actual);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("relative/path")]
    public void InvalidAddressIsRejectedBeforeShellHandoff(string? address)
    {
        Uri? uri = address is null ? null : new Uri(address, UriKind.Relative);
        bool launched = false;

        Assert.ThrowsAny<ArgumentException>(() =>
            WindowsExternalUriLauncher.Open(uri!, _ => launched = true));

        Assert.False(launched);
    }

    [Fact]
    public void MissingLauncherIsRejected()
    {
        Assert.Throws<ArgumentNullException>(() =>
            WindowsExternalUriLauncher.Open(new Uri("https://example.com/"), null!));
    }
}
