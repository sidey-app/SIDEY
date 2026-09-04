namespace Sidey.Infrastructure;

internal sealed class ExpiringLeaseRegistry<TKey> : IAsyncDisposable
    where TKey : notnull
{
    private readonly object _gate = new();
    private readonly Dictionary<TKey, Lease> _leases = [];
    private readonly CancellationTokenSource _shutdown = new();
    private readonly TimeSpan _duration;
    private readonly Action<TKey> _expired;
    private readonly Func<TimeSpan, CancellationToken, Task> _delay;
    private bool _disposed;

    internal ExpiringLeaseRegistry(
        TimeSpan duration,
        Action<TKey> expired,
        Func<TimeSpan, CancellationToken, Task>? delay = null)
    {
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(duration, TimeSpan.Zero);
        _duration = duration;
        _expired = expired ?? throw new ArgumentNullException(nameof(expired));
        _delay = delay ?? Task.Delay;
    }

    internal int Count
    {
        get
        {
            lock (_gate)
            {
                return _leases.Count;
            }
        }
    }

    internal void Restart(TKey key)
    {
        Lease replacement;
        Lease? previous;
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            _leases.Remove(key, out previous);
            replacement = new Lease(this, key, _shutdown.Token);
            _leases.Add(key, replacement);
        }

        previous?.Cancel();
    }

    internal void Cancel(TKey key)
    {
        Lease? lease;
        lock (_gate)
        {
            _leases.Remove(key, out lease);
        }

        lease?.Cancel();
    }

    public async ValueTask DisposeAsync()
    {
        Lease[] leases;
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            leases = _leases.Values.ToArray();
            _leases.Clear();
        }

        _shutdown.Cancel();
        try
        {
            await Task.WhenAll(leases.Select(lease => lease.Completion)).ConfigureAwait(false);
        }
        finally
        {
            _shutdown.Dispose();
        }
    }

    private async Task ExpireAsync(TKey key, Lease lease)
    {
        try
        {
            await _delay(_duration, lease.Token).ConfigureAwait(false);
            bool removed;
            lock (_gate)
            {
                removed = _leases.TryGetValue(key, out Lease? current)
                    && ReferenceEquals(current, lease)
                    && _leases.Remove(key);
            }

            if (removed)
            {
                _expired(key);
            }
        }
        catch (OperationCanceledException) when (lease.IsCancellationRequested)
        {
        }
        finally
        {
            lease.DisposeCancellation();
        }
    }

    private sealed class Lease
    {
        private readonly CancellationTokenSource _cancellation;

        internal Lease(
            ExpiringLeaseRegistry<TKey> owner,
            TKey key,
            CancellationToken shutdownToken)
        {
            _cancellation = CancellationTokenSource.CreateLinkedTokenSource(shutdownToken);
            Completion = owner.ExpireAsync(key, this);
        }

        internal Task Completion { get; }

        internal CancellationToken Token => _cancellation.Token;

        internal bool IsCancellationRequested => _cancellation.IsCancellationRequested;

        internal void Cancel()
        {
            try
            {
                _cancellation.Cancel();
            }
            catch (ObjectDisposedException)
            {
                // Expiration may win the race and dispose its source first.
            }
        }

        internal void DisposeCancellation() => _cancellation.Dispose();
    }
}
