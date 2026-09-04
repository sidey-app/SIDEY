using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;

namespace Sidey.Platform.Windows;

/// <summary>
/// Derives online/away only from elapsed time since the last system input and
/// whether the interactive input desktop is available. It never reads event
/// contents, keys, applications, screen pixels or pointer coordinates.
/// </summary>
public sealed class WindowsActivityMonitor(
    TimeSpan? awayThreshold = null,
    TimeSpan? sampleInterval = null) : IActivityMonitor
{
    private readonly TimeSpan _awayThreshold = awayThreshold ?? TimeSpan.FromMinutes(5);
    private readonly TimeSpan _sampleInterval = sampleInterval ?? TimeSpan.FromSeconds(1);
    private readonly CancellationTokenSource _shutdown = new();

    public async IAsyncEnumerable<PresenceState> ObserveAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken,
            _shutdown.Token);
        using var timer = new PeriodicTimer(_sampleInterval);
        PresenceState? previous = null;
        do
        {
            var state = CurrentState();
            if (state != previous)
            {
                previous = state;
                yield return state;
            }
        }
        while (await timer.WaitForNextTickAsync(linked.Token).ConfigureAwait(false));
    }

    public ValueTask DisposeAsync()
    {
        _shutdown.Cancel();
        _shutdown.Dispose();
        return ValueTask.CompletedTask;
    }

    public PresenceState CurrentState()
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("Windows activity state is required.");
        }

        var input = new LastInputInfo { Size = (uint)Marshal.SizeOf<LastInputInfo>() };
        if (!NativeMethods.GetLastInputInfo(ref input))
        {
            return PresenceState.Away;
        }

        var elapsedMilliseconds = unchecked((uint)Environment.TickCount64 - input.Time);
        return IsScreenLocked() || elapsedMilliseconds >= _awayThreshold.TotalMilliseconds
            ? PresenceState.Away
            : PresenceState.Online;
    }

    private static bool IsScreenLocked()
    {
        var desktop = NativeMethods.OpenInputDesktop(0, false, 0x0001);
        if (desktop == nint.Zero)
        {
            return true;
        }
        NativeMethods.CloseDesktop(desktop);
        return false;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LastInputInfo
    {
        public uint Size;
        public uint Time;
    }

    private static class NativeMethods
    {
        [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LastInputInfo info);
        [DllImport("user32.dll")] public static extern nint OpenInputDesktop(uint flags, bool inherit, uint access);
        [DllImport("user32.dll")] public static extern bool CloseDesktop(nint desktop);
    }
}
