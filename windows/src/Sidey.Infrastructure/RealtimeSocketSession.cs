using System.Net.WebSockets;

namespace Sidey.Infrastructure;

internal sealed class RealtimeSocketSession : IAsyncDisposable
{
    private readonly Task _receiveTask;
    private bool _disposed;

    internal RealtimeSocketSession(
        ClientWebSocket socket,
        Func<ClientWebSocket, Task> receiveLoop)
    {
        Socket = socket ?? throw new ArgumentNullException(nameof(socket));
        ArgumentNullException.ThrowIfNull(receiveLoop);
        _receiveTask = receiveLoop(Socket);
    }

    internal ClientWebSocket Socket { get; }

    public async ValueTask DisposeAsync()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        Socket.Abort();
        try
        {
            await _receiveTask.ConfigureAwait(false);
        }
        finally
        {
            Socket.Dispose();
        }
    }
}
