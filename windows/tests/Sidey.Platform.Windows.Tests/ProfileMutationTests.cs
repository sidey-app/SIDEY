using System.Reflection;
using Sidey.Core.Abstractions;
using Sidey.Infrastructure;

namespace Sidey.Platform.Windows.Tests;

public sealed class ProfileMutationTests
{
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("unknown")]
    public async Task InvalidCharacterCannotBecomeASavedHamster(string? characterId)
    {
        ICredentialStore credentials = DispatchProxy.Create<ICredentialStore, UnusedCredentials>();
        var configuration = new SupabaseRuntimeConfiguration(new Uri("https://example.invalid"), "test-key");
        using var auth = new SupabaseAnonymousAuthService(configuration, credentials);
        await using var backend = new SupabaseBackendGateway(configuration, auth, credentials);

        ArgumentException exception = await Assert.ThrowsAsync<ArgumentException>(
            () => backend.SaveProfileAsync("Friend", characterId!));

        Assert.Equal("characterId", exception.ParamName);
    }

    public class UnusedCredentials : DispatchProxy
    {
        protected override object? Invoke(MethodInfo? targetMethod, object?[]? args) =>
            throw new InvalidOperationException("Invalid selection must be rejected before accessing a session.");
    }
}
