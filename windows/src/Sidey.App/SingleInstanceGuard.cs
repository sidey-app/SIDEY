namespace Sidey.App;

internal sealed class SingleInstanceGuard : IDisposable
{
    private const string MutexName = "Local\\SIDEY.app.sidey.desktop";
    private const string ActivateEventName = "Local\\SIDEY.app.sidey.desktop.activate";
    private readonly Mutex _mutex;
    private readonly EventWaitHandle _activateEvent;
    private RegisteredWaitHandle? _activateWait;

    private SingleInstanceGuard(
        Mutex mutex,
        EventWaitHandle activateEvent,
        bool isPrimary)
    {
        _mutex = mutex;
        _activateEvent = activateEvent;
        IsPrimary = isPrimary;
    }

    public bool IsPrimary { get; }

    public static SingleInstanceGuard Acquire()
    {
        var mutex = new Mutex(initiallyOwned: true, MutexName, out var createdNew);
        var activateEvent = new EventWaitHandle(
            false,
            EventResetMode.AutoReset,
            ActivateEventName);
        return new SingleInstanceGuard(mutex, activateEvent, createdNew);
    }

    public void StartListening(Action activate)
    {
        if (!IsPrimary || _activateWait is not null)
        {
            return;
        }

        ArgumentNullException.ThrowIfNull(activate);
        _activateWait = ThreadPool.RegisterWaitForSingleObject(
            _activateEvent,
            (_, timedOut) =>
            {
                if (!timedOut)
                {
                    activate();
                }
            },
            state: null,
            Timeout.Infinite,
            executeOnlyOnce: false);
    }

    public void Signal() => _activateEvent.Set();

    public void Dispose()
    {
        _activateWait?.Unregister(null);
        _activateWait = null;
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
        _activateEvent.Dispose();
        _mutex.Dispose();
    }
}
