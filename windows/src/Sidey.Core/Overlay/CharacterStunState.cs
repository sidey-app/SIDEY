using System.Diagnostics;

namespace Sidey.Core.Overlay;

/// <summary>Transient, scene-local hit state. The clock is monotonic; no network state is changed.</summary>
public sealed class CharacterStunState(Func<double>? clock = null)
{
    public const double WindowSeconds = 10;
    public const double DurationSeconds = 6;
    public const int HitThreshold = 10;
    private readonly Func<double> _clock = clock ?? (() => (double)Stopwatch.GetTimestamp() / Stopwatch.Frequency);
    private readonly Lock _gate = new();
    private readonly Dictionary<Guid, Queue<double>> _hits = [];
    private readonly Dictionary<Guid, double> _started = [];

    public double? Elapsed(Guid id)
    {
        lock (_gate)
        {
            double now = _clock();
            if (_started.TryGetValue(id, out double start) && now < start + DurationSeconds)
                return Math.Max(0, now - start);
            _started.Remove(id);
            return null;
        }
    }

    public bool IsStunned(Guid id) => Elapsed(id) is not null;

    public bool RecordHit(Guid id)
    {
        lock (_gate)
        {
            if (IsStunned(id))
                return false;
            double now = _clock();
            if (!_hits.TryGetValue(id, out Queue<double>? hits))
                _hits[id] = hits = new Queue<double>();
            while (hits.TryPeek(out double hit) && hit < now - WindowSeconds)
                hits.Dequeue();
            hits.Enqueue(now);
            if (hits.Count < HitThreshold)
                return false;
            _hits.Remove(id);
            _started[id] = now;
            return true;
        }
    }

    public void Remove(Guid id)
    {
        lock (_gate)
        { _hits.Remove(id); _started.Remove(id); }
    }

    public void Reset()
    {
        lock (_gate)
        { _hits.Clear(); _started.Clear(); }
    }
}
