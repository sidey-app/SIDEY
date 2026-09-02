namespace Sidey.App;

internal enum SingleInstanceRequest
{
    Activate,
    OnboardingPreview,
}

internal sealed class SingleInstanceGuard : IDisposable
{
    private const string MutexName = "Local\\SIDEY.app.sidey.desktop";
    private const string ActivateEventName = "Local\\SIDEY.app.sidey.desktop.activate";
    private const string PreviewEventName = "Local\\SIDEY.app.sidey.desktop.onboarding-preview";
    private readonly Mutex _mutex;
    private readonly EventWaitHandle _activateEvent;
    private readonly EventWaitHandle _previewEvent;
    private RegisteredWaitHandle? _activateWait;
    private RegisteredWaitHandle? _previewWait;

    private SingleInstanceGuard(
        Mutex mutex,
        EventWaitHandle activateEvent,
        EventWaitHandle previewEvent,
        bool isPrimary)
    {
        _mutex = mutex;
        _activateEvent = activateEvent;
        _previewEvent = previewEvent;
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
        var previewEvent = new EventWaitHandle(
            false,
            EventResetMode.AutoReset,
            PreviewEventName);
        return new SingleInstanceGuard(mutex, activateEvent, previewEvent, createdNew);
    }

    public void StartListening(Action activate, Action onboardingPreview)
    {
        if (!IsPrimary || _activateWait is not null || _previewWait is not null)
        {
            return;
        }

        ArgumentNullException.ThrowIfNull(activate);
        ArgumentNullException.ThrowIfNull(onboardingPreview);
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
        _previewWait = ThreadPool.RegisterWaitForSingleObject(
            _previewEvent,
            (_, timedOut) =>
            {
                if (!timedOut)
                {
                    onboardingPreview();
                }
            },
            state: null,
            Timeout.Infinite,
            executeOnlyOnce: false);
    }

    public void Signal(SingleInstanceRequest request)
    {
        EventWaitHandle target = request == SingleInstanceRequest.OnboardingPreview
            ? _previewEvent
            : _activateEvent;
        target.Set();
    }

    public void Dispose()
    {
        _activateWait?.Unregister(null);
        _activateWait = null;
        _previewWait?.Unregister(null);
        _previewWait = null;
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
        _previewEvent.Dispose();
        _mutex.Dispose();
    }
}
