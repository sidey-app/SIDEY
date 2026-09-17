using Sidey.Infrastructure;
using Windows.Networking.Connectivity;

namespace Sidey.Platform.Windows.Tests;

public sealed class RealtimeNetworkAvailabilityTests
{
    [Theory]
    [InlineData(null, false)]
    [InlineData(NetworkConnectivityLevel.None, false)]
    [InlineData(NetworkConnectivityLevel.LocalAccess, true)]
    [InlineData(NetworkConnectivityLevel.ConstrainedInternetAccess, true)]
    [InlineData(NetworkConnectivityLevel.InternetAccess, true)]
    public void OnlyDefinitePathLossBlocksServiceAttempts(NetworkConnectivityLevel? level, bool expected) =>
        Assert.Equal(expected, SystemNetworkAvailabilityMonitor.CanAttemptConnection(level));

    [Fact]
    public void PathChangesCanRequestRecoveryWithoutAnOfflineOnlineTransition()
    {
        using var monitor = new SystemNetworkAvailabilityMonitor(() => true);
        int hints = 0;
        monitor.PathChanged += () => hints++;
        monitor.Start();
        monitor.Refresh();
        Assert.Equal(0, hints);
        monitor.Refresh(notifyPathChange: true);
        Assert.Equal(1, hints);
        monitor.Dispose();
        monitor.Refresh(notifyPathChange: true);
        Assert.Equal(1, hints);
    }

    [Fact]
    public void MonitorRefreshEmitsOnlyChangedConnectivityAndStopsAfterDisposal()
    {
        bool available = true;
        using var monitor = new SystemNetworkAvailabilityMonitor(() => available);
        var changes = new List<bool>();
        monitor.AvailabilityChanged += changes.Add;
        monitor.Start();
        available = false;
        monitor.Refresh();
        monitor.Refresh();
        Assert.False(monitor.IsAvailable);
        available = true;
        monitor.Refresh();
        Assert.True(monitor.IsAvailable);
        monitor.Dispose();
        available = false;
        monitor.Refresh();
        Assert.Equal(new[] { false, true }, changes);
    }
}
