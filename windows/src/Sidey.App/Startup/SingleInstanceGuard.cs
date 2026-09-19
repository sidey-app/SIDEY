using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text;

namespace Sidey.App.Startup;

internal sealed class SingleInstanceGuard : IDisposable
{
    private const string MutexName = "Local\\SIDEY.app.sidey.desktop";
    private const string ActivationPipeName = "SIDEY.app.sidey.desktop.activate";
    private const int MaximumActivationBytes = 4096;
    private readonly Mutex _mutex;
    private readonly string _activationPipeName;
    private readonly ISingleInstanceForegroundPermission _foregroundPermission;
    private readonly CancellationTokenSource _listening = new();
    private Task? _activationTask;

    private SingleInstanceGuard(
        Mutex mutex,
        bool isPrimary,
        string activationPipeName,
        ISingleInstanceForegroundPermission foregroundPermission)
    {
        _mutex = mutex;
        IsPrimary = isPrimary;
        _activationPipeName = activationPipeName;
        _foregroundPermission = foregroundPermission;
    }

    public bool IsPrimary { get; }

    public static SingleInstanceGuard Acquire(string? smokeDataRoot = null)
    {
        // The startup harness already isolates its data; isolate activation too so it cannot target a user's app.
        string suffix = string.IsNullOrWhiteSpace(smokeDataRoot) ? string.Empty
            : ".smoke." + Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(smokeDataRoot)))[..24];
        var mutex = new Mutex(initiallyOwned: true, MutexName + suffix, out bool createdNew);
        return new SingleInstanceGuard(
            mutex,
            createdNew,
            ActivationPipeName + suffix,
            new NativeSingleInstanceForegroundPermission());
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
        Signal(_activationPipeName, activationArgument, _foregroundPermission);
    }

    internal static void Signal(
        string activationPipeName,
        string? activationArgument,
        ISingleInstanceForegroundPermission foregroundPermission)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(activationPipeName);
        ArgumentNullException.ThrowIfNull(foregroundPermission);
        byte[] payload = Encoding.UTF8.GetBytes(activationArgument ?? string.Empty);
        if (payload.Length > MaximumActivationBytes)
        {
            payload = [];
        }
        using var pipe = new NamedPipeClientStream(
            ".",
            activationPipeName,
            PipeDirection.Out,
            PipeOptions.CurrentUserOnly);
        pipe.Connect(10000);
        TryGrantForegroundPermission(pipe, foregroundPermission);
        pipe.Write(payload);
    }

    private static void TryGrantForegroundPermission(
        NamedPipeClientStream pipe,
        ISingleInstanceForegroundPermission foregroundPermission)
    {
        try
        {
            if (foregroundPermission.TryGetServerProcessId(pipe, out uint processId)
                && processId != 0)
            {
                _ = foregroundPermission.AllowSetForegroundWindow(processId);
            }
        }
        catch (Exception)
        {
            // Foreground permission is best effort; activation delivery must still continue.
        }
    }

    private async Task ListenAsync(
        Action<string?> activate,
        CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await using var pipe = new NamedPipeServerStream(
                    _activationPipeName,
                    PipeDirection.In,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await pipe.WaitForConnectionAsync(cancellationToken);
                byte[] buffer = new byte[MaximumActivationBytes + 1];
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

internal interface ISingleInstanceForegroundPermission
{
    public bool TryGetServerProcessId(NamedPipeClientStream pipe, out uint processId);

    public bool AllowSetForegroundWindow(uint processId);
}

internal sealed class NativeSingleInstanceForegroundPermission : ISingleInstanceForegroundPermission
{
    public bool TryGetServerProcessId(NamedPipeClientStream pipe, out uint processId) =>
        NativeMethods.GetNamedPipeServerProcessId(pipe.SafePipeHandle, out processId);

    public bool AllowSetForegroundWindow(uint processId) =>
        NativeMethods.AllowSetForegroundWindow(processId);

    private static class NativeMethods
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetNamedPipeServerProcessId(
            Microsoft.Win32.SafeHandles.SafePipeHandle pipe,
            out uint serverProcessId);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool AllowSetForegroundWindow(uint processId);
    }
}
