using Sidey.Core.Abstractions;

namespace Sidey.Core.Tests;

public sealed class AuthPolicyTests
{
    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task MissingSessionRequiresProviderAuthenticationForEveryInstallation(bool hasStoredSession)
    {
        var auth = new FakeAuthService();
        await Assert.ThrowsAsync<AuthenticationRequiredException>(() => SessionBootstrapper.RestoreAsync(auth, hasStoredSession));
        Assert.Equal(1, auth.RestoreCount);
    }

    [Fact]
    public async Task ExistingSessionRetainsItsCanonicalUser()
    {
        var session = new AuthSession(Guid.NewGuid(), DateTimeOffset.Parse("2026-01-01T00:00:00Z"));
        var auth = new FakeAuthService { Restored = session };
        Assert.Equal(session, await SessionBootstrapper.RestoreAsync(auth, hasStoredSession: true));
    }

    [Fact]
    public async Task LegacyClaimRequirementIsNotHiddenAsGenericRecoveryFailure()
    {
        var auth = new FakeAuthService { Failure = new LegacyClaimRequiredException() };
        await Assert.ThrowsAsync<LegacyClaimRequiredException>(() => SessionBootstrapper.RestoreAsync(auth, hasStoredSession: true));
    }

    [Fact]
    public async Task CancelledRestoreDoesNotBecomeAccountRecoveryFailure()
    {
        var auth = new FakeAuthService { Failure = new OperationCanceledException() };
        await Assert.ThrowsAsync<OperationCanceledException>(() => SessionBootstrapper.RestoreAsync(auth, hasStoredSession: true));
    }

    private sealed class FakeAuthService : IAuthService
    {
        public AuthSession? Restored { get; init; }
        public Exception? Failure { get; init; }
        public int RestoreCount { get; private set; }

        public Task<AuthSession?> RestoreSessionAsync(CancellationToken cancellationToken = default)
        {
            RestoreCount++;
            return Failure is null ? Task.FromResult(Restored) : Task.FromException<AuthSession?>(Failure);
        }

        public Task SignOutAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
    }
}
