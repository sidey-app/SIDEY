using Sidey.Core.Abstractions;

namespace Sidey.Core.Tests;

public sealed class AuthPolicyTests
{
    [Fact]
    public async Task ExistingInstallationNeverCreatesReplacementAnonymousAccount()
    {
        var auth = new FakeAuthService { Restored = null };

        await Assert.ThrowsAsync<SessionRecoveryException>(() =>
            AnonymousSessionBootstrapper.RestoreOrCreateAsync(auth, hasStoredSession: true));

        Assert.Equal(0, auth.CreatedCount);
    }

    [Fact]
    public async Task NewInstallationCreatesAnonymousAccountOnlyWhenNothingCanBeRestored()
    {
        var auth = new FakeAuthService { Restored = null };

        var session = await AnonymousSessionBootstrapper.RestoreOrCreateAsync(
            auth,
            hasStoredSession: false);

        Assert.Equal(auth.Created, session);
        Assert.Equal(1, auth.CreatedCount);
    }

    private sealed class FakeAuthService : IAuthService
    {
        public AuthSession? Restored { get; init; }
        public AuthSession Created { get; } = new(Guid.NewGuid(), DateTimeOffset.UtcNow.AddHours(1));
        public int CreatedCount { get; private set; }

        public Task<AuthSession?> RestoreSessionAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult(Restored);

        public Task<AuthSession> CreateAnonymousSessionAsync(CancellationToken cancellationToken = default)
        {
            CreatedCount++;
            return Task.FromResult(Created);
        }

        public Task SignOutAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
    }
}
