using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Infrastructure;

namespace Sidey.Platform.Windows.Tests;

public sealed class RealtimeNetworkAvailabilityTests
{
    [Fact]
    public async Task SynchronizationDefersWithoutReadingAuthWhileNetworkIsUnavailable()
    {
        var network = new FakeNetworkAvailabilityMonitor(isAvailable: false);
        var sessions = new CountingSessionAccessor();
        await using (var transport = new SupabaseRealtimeTransport(
            new SupabaseRuntimeConfiguration(new Uri("http://localhost"), "test-key"),
            sessions,
            network))
        {
            await transport.SynchronizeAsync(
                new Dictionary<Guid, long>(),
                activeRoomId: null,
                PresenceState.Online,
                CancellationToken.None);

            Assert.Equal(0, sessions.ReadCount);
            Assert.Equal(RealtimeConnectionStatus.Disconnected, transport.ConnectionStatus);
            Assert.True(network.Started);
        }

        Assert.True(network.Disposed);
    }

    private sealed class FakeNetworkAvailabilityMonitor(bool isAvailable)
        : INetworkAvailabilityMonitor
    {
        public bool IsAvailable { get; } = isAvailable;
        public bool Started { get; private set; }
        public bool Disposed { get; private set; }

        public event Action<bool>? AvailabilityChanged
        {
            add { }
            remove { }
        }

        public void Start() => Started = true;

        public void Dispose()
        {
            Disposed = true;
        }
    }

    private sealed class CountingSessionAccessor : IAuthSessionAccessor
    {
        public int ReadCount { get; private set; }

        public ValueTask<StoredSupabaseSession?> GetStoredSessionAsync(
            CancellationToken cancellationToken = default)
        {
            _ = cancellationToken;
            ReadCount++;
            return ValueTask.FromResult<StoredSupabaseSession?>(null);
        }
    }
}
