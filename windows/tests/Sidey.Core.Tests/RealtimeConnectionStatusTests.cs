using Sidey.Core.Abstractions;

namespace Sidey.Core.Tests;

public sealed class RealtimeConnectionStatusTests
{
    [Fact]
    public void ReadyRequiresTransportAndRecoveryWhileActiveRoomCanRecoverEarlier()
    {
        var activeRoomReady = new RealtimeConnectionStatus(
            TransportConnected: true,
            ActiveRoomTransportConnected: true,
            RecoveryReconciled: false);

        Assert.False(activeRoomReady.IsReady);
        Assert.True(activeRoomReady.ActiveRoomTransportConnected);
        Assert.True(activeRoomReady.WithRecoveryReconciled(true).IsReady);
    }

    [Fact]
    public void DisconnectedTransportCannotBeMarkedReconciled()
    {
        RealtimeConnectionStatus status = RealtimeConnectionStatus.Disconnected
            .WithRecoveryReconciled(true);

        Assert.False(status.IsReady);
        Assert.False(status.RecoveryReconciled);
    }
}
