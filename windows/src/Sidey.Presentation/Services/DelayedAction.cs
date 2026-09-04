using System.Diagnostics;

namespace Sidey.Presentation.Services;

internal sealed class DelayedAction
{
    private readonly CancellationTokenSource _cancellation = new();

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

    internal void Cancel() => _cancellation.Cancel();

    private async Task RunAsync(TimeSpan delay, Action action)
    {
        try
        {
            await Task.Delay(delay, _cancellation.Token);
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
            _cancellation.Dispose();
        }
    }
}
