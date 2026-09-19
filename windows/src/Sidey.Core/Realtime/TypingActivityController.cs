namespace Sidey.Core.Realtime;

/// <summary>Actual edits own the idle deadline; transient sends share one ordered lane.</summary>
public sealed class TypingActivityController : IAsyncDisposable
{
    public static readonly TimeSpan StartDelay = TimeSpan.FromMilliseconds(500);
    public static readonly TimeSpan RefreshInterval = TimeSpan.FromSeconds(2);
    public static readonly TimeSpan IdleTimeout = TimeSpan.FromSeconds(5);
    private readonly Lock _gate = new();
    private readonly TimeProvider _clock;
    private readonly Func<Guid, bool, bool, CancellationToken, Task> _send;
    private readonly Action<Guid, bool> _local;
    private readonly CancellationTokenSource _shutdown = new();
    private readonly ITimer _timer;
    private Task _tail = Task.CompletedTask;
    private Activity? _activity;
    private bool _disposed;

    private sealed class Activity(Guid roomId, long now)
    {
        public Guid RoomId { get; } = roomId;
        public long FirstEdit { get; } = now;
        public long LastEdit { get; set; } = now;
        public long? LastAttempt { get; set; }
        public bool Dirty { get; set; } = true;
        public bool Pending { get; set; }
        public bool Attempted { get; set; }
    }

    public TypingActivityController(
        Func<Guid, bool, bool, CancellationToken, Task> send,
        Action<Guid, bool> local,
        TimeProvider? clock = null)
    {
        _send = send;
        _local = local;
        _clock = clock ?? TimeProvider.System;
        _timer = _clock.CreateTimer(_ => Tick(), null, Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
    }

    public void Edit(Guid roomId)
    {
        lock (_gate)
        {
            if (_disposed)
                return;
            if (_activity?.RoomId != roomId)
            {
                StopCore();
                _activity = new Activity(roomId, _clock.GetTimestamp());
                _local(roomId, true);
            }
            _activity.LastEdit = _clock.GetTimestamp();
            _activity.Dirty = true;
            Schedule();
        }
    }

    public void Stop()
    {
        lock (_gate)
        {
            if (!_disposed)
                StopCore();
        }
    }

    private void StopCore()
    {
        _timer.Change(Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
        if (_activity is not { } activity)
            return;
        _activity = null;
        _local(activity.RoomId, false);
        Task previous = _tail;
        _tail = SendStopAsync(previous, activity);
    }

    private async Task SendStopAsync(Task previous, Activity activity)
    {
        await previous.ConfigureAwait(false);
        // A canceled queued start needs no stop. An attempted start does, even on failure.
        if (activity.Attempted)
            await SendSafelyAsync(activity.RoomId, false, false).ConfigureAwait(false);
    }

    private void Tick()
    {
        lock (_gate)
        {
            if (_disposed || _activity is not { } activity)
                return;
            long now = _clock.GetTimestamp();
            if (_clock.GetElapsedTime(activity.LastEdit, now) >= IdleTimeout)
            {
                StopCore();
                return;
            }
            if (activity.Dirty && !activity.Pending && UntilEmission(activity, now) <= TimeSpan.Zero)
            {
                activity.Pending = true;
                Task previous = _tail;
                _tail = SendActiveAsync(previous, activity);
            }
            Schedule();
        }
    }

    private async Task SendActiveAsync(Task previous, Activity activity)
    {
        await previous.ConfigureAwait(false);
        bool keepalive;
        lock (_gate)
        {
            if (_disposed || _activity != activity)
                return;
            if (_clock.GetElapsedTime(activity.LastEdit, _clock.GetTimestamp()) >= IdleTimeout)
            {
                StopCore();
                return;
            }
            keepalive = activity.Attempted;
            activity.Attempted = true;
            activity.LastAttempt = _clock.GetTimestamp();
            activity.Dirty = false;
        }
        bool succeeded = await SendSafelyAsync(activity.RoomId, true, keepalive).ConfigureAwait(false);
        lock (_gate)
        {
            activity.Pending = false;
            // Failure is not a retry trigger, including edits made while the request was in flight.
            if (!succeeded)
                activity.Dirty = false;
            if (!_disposed && _activity == activity)
                Schedule();
        }
    }

    private async Task<bool> SendSafelyAsync(Guid roomId, bool active, bool keepalive)
    {
        try
        {
            await _send(roomId, active, keepalive, _shutdown.Token).ConfigureAwait(false);
            return true;
        }
        catch (Exception)
        {
            // Typing is best effort. Authentication and connection recovery belong to the transport.
            return false;
        }
    }

    private TimeSpan UntilEmission(Activity activity, long now) => activity.LastAttempt is { } last
        ? RefreshInterval - _clock.GetElapsedTime(last, now)
        : StartDelay - _clock.GetElapsedTime(activity.FirstEdit, now);

    private void Schedule()
    {
        if (_activity is not { } activity)
            return;
        long now = _clock.GetTimestamp();
        TimeSpan delay = IdleTimeout - _clock.GetElapsedTime(activity.LastEdit, now);
        if (activity.Dirty && !activity.Pending)
        {
            TimeSpan emission = UntilEmission(activity, now);
            if (emission < delay)
                delay = emission;
        }
        _timer.Change(delay > TimeSpan.Zero ? delay : TimeSpan.Zero, Timeout.InfiniteTimeSpan);
    }

    public async ValueTask DisposeAsync()
    {
        Task pending;
        lock (_gate)
        {
            if (_disposed)
                return;
            _disposed = true;
            StopCore();
            _timer.Dispose();
            pending = _tail;
        }
        // Bound shutdown while giving an in-flight start and its following stop time to drain.
        _shutdown.CancelAfter(TimeSpan.FromSeconds(3));
        try
        { await pending.ConfigureAwait(false); }
        finally { _shutdown.Dispose(); }
    }
}
