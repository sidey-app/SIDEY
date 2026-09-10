namespace Sidey.Core.Overlay;

public sealed class ImpactSoundAdmission
{
    private double _lastStart = double.NegativeInfinity;
    public bool Accept(double now, double requestedAt, int activeVoices, bool enabled)
    {
        if (!enabled || !double.IsFinite(now) || !double.IsFinite(requestedAt)
            || requestedAt > now || now - requestedAt > 0.5 || activeVoices >= 4 || now - _lastStart < 0.08)
            return false;
        _lastStart = now;
        return true;
    }
    public void Reset() => _lastStart = double.NegativeInfinity;
}
