using Sidey.Core.Domain;

namespace Sidey.Overlay;

internal sealed class CharacterPulseReplayGuard(int capacity = 256)
{
    private readonly int _capacity = capacity > 0
        ? capacity
        : throw new ArgumentOutOfRangeException(nameof(capacity));
    private readonly HashSet<Guid> _ids = [];
    private readonly Queue<Guid> _order = [];

    internal void SeedExisting(IEnumerable<CharacterPulseEvent> pulses)
    {
        foreach (var pulse in pulses)
        {
            Remember(pulse.Id);
        }
    }

    internal bool TryAccept(CharacterPulseEvent pulse) => Remember(pulse.Id);

    private bool Remember(Guid pulseId)
    {
        if (!_ids.Add(pulseId))
        {
            return false;
        }

        _order.Enqueue(pulseId);
        while (_order.Count > _capacity)
        {
            _ids.Remove(_order.Dequeue());
        }
        return true;
    }
}
