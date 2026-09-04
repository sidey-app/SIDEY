using System.Net.WebSockets;
using Sidey.Infrastructure;

namespace Sidey.Platform.Windows.Tests;

public sealed class RealtimeSocketSessionTests
{
    [Fact]
    public async Task DisposeWaitsForTheReceiveLoopBeforeCompleting()
    {
        var receiveLoopRelease = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var socket = new ClientWebSocket();
        var session = new RealtimeSocketSession(
            socket,
            async _ => await receiveLoopRelease.Task);

        Task disposal = session.DisposeAsync().AsTask();

        Assert.False(disposal.IsCompleted);
        receiveLoopRelease.SetResult();
        await disposal;
    }
}
