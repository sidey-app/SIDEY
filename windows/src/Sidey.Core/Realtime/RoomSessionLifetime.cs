namespace Sidey.Core.Realtime;

/// <summary>Owns background room work and drains it before its backend is disposed.</summary>
public sealed class RoomSessionLifetime : IAsyncDisposable
{
    private readonly CancellationTokenSource _shutdown = new();
    private readonly Lock _gate = new();
    private readonly List<Task> _retiredTyping = [];
    private CancellationTokenSource? _typingCancellation;
    private Task? _typingTask;
    private Task? _disposeTask;
    public CancellationToken Token { get; }
    public bool IsCancellationRequested => Token.IsCancellationRequested;
    public RoomSwitchPipeline? SwitchPipeline { get; set; }
    public Task? EventPump { get; set; }
    public Task? ActivityPump { get; set; }

    public RoomSessionLifetime() => Token = _shutdown.Token;

    public void StartTyping(Func<CancellationToken, Task> run)
    {
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposeTask is not null, this);
            StopTypingCore();
            var cancellation = CancellationTokenSource.CreateLinkedTokenSource(Token);
            try
            {
                _typingTask = run(cancellation.Token);
                _typingCancellation = cancellation;
            }
            catch
            {
                cancellation.Dispose();
                throw;
            }
        }
    }

    public void StopTyping()
    {
        lock (_gate)
            StopTypingCore();
    }

    private void StopTypingCore()
    {
        if (_typingCancellation is not { } cancellation)
            return;
        Task task = _typingTask ?? Task.CompletedTask;
        _typingCancellation = null;
        _typingTask = null;
        cancellation.Cancel();
        _retiredTyping.RemoveAll(task => task.IsCompletedSuccessfully);
        _retiredTyping.Add(DrainTypingAsync(task, cancellation));
    }

    private static async Task DrainTypingAsync(Task task, CancellationTokenSource cancellation)
    {
        try
        { await task.ConfigureAwait(false); }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
        finally { cancellation.Dispose(); }
    }

    public ValueTask DisposeAsync()
    {
        lock (_gate)
        {
            _disposeTask ??= DisposeCoreAsync();
            return new ValueTask(_disposeTask);
        }
    }

    private async Task DisposeCoreAsync()
    {
        _shutdown.Cancel();
        StopTypingCore();
        try
        {
            if (SwitchPipeline is not null)
                await SwitchPipeline.DisposeAsync().ConfigureAwait(false);
            await Task.WhenAll(_retiredTyping.Append(EventPump ?? Task.CompletedTask)
                .Append(ActivityPump ?? Task.CompletedTask)).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (Token.IsCancellationRequested) { }
        finally { _shutdown.Dispose(); }
    }
}
