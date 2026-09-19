namespace Sidey.Presentation.Services;

/// <summary>Delivers only the latest local typing state on the presentation owner thread.</summary>
public sealed class TypingFeedbackDispatcher(
    Action<Action> dispatch,
    Action<Guid, bool> apply) : IDisposable
{
    private readonly Lock _gate = new();
    private long _revision;
    private bool _disposed;

    public void Publish(Guid roomId, bool active)
    {
        long revision;
        lock (_gate)
        {
            if (_disposed)
                return;
            revision = ++_revision;
        }
        dispatch(() =>
        {
            lock (_gate)
            {
                // A queued idle-stop must not clear feedback from a newer immediate edit.
                if (!_disposed && revision == _revision)
                    apply(roomId, active);
            }
        });
    }

    public void Dispose()
    {
        lock (_gate)
            _disposed = true;
    }
}
