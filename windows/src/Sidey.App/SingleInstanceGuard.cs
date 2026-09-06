using System.IO.Pipes;
using System.Text;

namespace Sidey.App;

internal sealed class SingleInstanceGuard : IDisposable
{
    private const string MutexName = "Local\\SIDEY.app.sidey.desktop";
    private const string ActivationPipeName = "SIDEY.app.sidey.desktop.activate";
    private const int MaximumActivationBytes = 4096;
    private readonly Mutex _mutex;
    private readonly CancellationTokenSource _listening = new();
    private Task? _activationTask;

    private SingleInstanceGuard(
        Mutex mutex,
        bool isPrimary)
    {
        _mutex = mutex;
        IsPrimary = isPrimary;
    }

    public bool IsPrimary { get; }

    public static SingleInstanceGuard Acquire()
    {
        var mutex = new Mutex(initiallyOwned: true, MutexName, out var createdNew);
        return new SingleInstanceGuard(mutex, createdNew);
    }

    public void StartListening(Action<string?> activate)
    {
        if (!IsPrimary || _activationTask is not null)
        {
            return;
        }

        ArgumentNullException.ThrowIfNull(activate);
        _activationTask = Task.Run(() => ListenAsync(activate, _listening.Token));
    }

    public void Signal(string? activationArgument)
    {
        byte[] payload = Encoding.UTF8.GetBytes(activationArgument ?? string.Empty);
        if (payload.Length > MaximumActivationBytes)
        {
            payload = [];
        }
        using var pipe = new NamedPipeClientStream(
            ".",
            ActivationPipeName,
            PipeDirection.Out,
            PipeOptions.CurrentUserOnly);
        pipe.Connect(10000);
        pipe.Write(payload);
    }

    private static async Task ListenAsync(
        Action<string?> activate,
        CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await using var pipe = new NamedPipeServerStream(
                    ActivationPipeName,
                    PipeDirection.In,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await pipe.WaitForConnectionAsync(cancellationToken);
                var buffer = new byte[MaximumActivationBytes + 1];
                int count = 0;
                while (count < buffer.Length)
                {
                    int read = await pipe.ReadAsync(buffer.AsMemory(count), cancellationToken);
                    if (read == 0)
                    {
                        break;
                    }
                    count += read;
                }
                string? argument = count is 0 or > MaximumActivationBytes
                    ? null
                    : Encoding.UTF8.GetString(buffer, 0, count);
                activate(argument);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                return;
            }
            catch (IOException)
            {
            }
        }
    }

    public void Dispose()
    {
        _listening.Cancel();
        if (IsPrimary)
        {
            try
            {
                _mutex.ReleaseMutex();
            }
            catch (ApplicationException)
            {
            }
        }
        _listening.Dispose();
        _mutex.Dispose();
    }
}
