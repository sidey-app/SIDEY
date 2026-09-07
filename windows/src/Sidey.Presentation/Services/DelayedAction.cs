using System.Diagnostics;

namespace Sidey.Presentation.Services;

internal sealed class DelayedAction
{
    private readonly CancellationTokenSource _cancellation = new();
    private readonly object _lifetimeGate = new();
    private bool _disposed;

    private DelayedAction(TimeSpan delay, Action action)
    {
        Completion = RunAsync(delay, action);
    }

    internal Task Completion { get; }

    internal static DelayedAction Start(TimeSpan delay, Action action)
    {
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(delay, TimeSpan.Zero);
        ArgumentNullException.ThrowIfNull(action);
        return new DelayedAction(delay, action);
    }

    internal void Cancel()
    {
        lock (_lifetimeGate)
        {
            // A dispatcher callback can cancel this action after its delay has finished.
            if (!_disposed)
            {
                _cancellation.Cancel();
            }
        }
    }

    private async Task RunAsync(TimeSpan delay, Action action)
    {
        try
        {
            CancellationToken token = _cancellation.Token;
            await Task.Delay(delay, token);
            token.ThrowIfCancellationRequested();
            action();
        }
        catch (OperationCanceledException) when (_cancellation.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            Trace.TraceError("SIDEY delayed UI action failed: {0}", exception);
        }
        finally
        {
            lock (_lifetimeGate)
            {
                _disposed = true;
                _cancellation.Dispose();
            }
        }
    }
}
