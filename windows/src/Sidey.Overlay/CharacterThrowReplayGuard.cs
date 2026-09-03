using Sidey.Core.Domain;

namespace Sidey.Overlay;

internal sealed class CharacterThrowReplayGuard(int capacity = 256)
{
    private readonly int _capacity = capacity > 0
        ? capacity
        : throw new ArgumentOutOfRangeException(nameof(capacity));
    private readonly Queue<Guid> _order = new(capacity);
    private readonly HashSet<Guid> _ids = new();

    internal void SeedExisting(IEnumerable<CharacterThrowEvent> events)
    {
        foreach (var characterThrow in events)
        {
            Remember(characterThrow.Id);
        }
    }

    internal bool TryAccept(CharacterThrowEvent characterThrow) => Remember(characterThrow.Id);

    private bool Remember(Guid id)
    {
        if (id == Guid.Empty || !_ids.Add(id))
        {
            return false;
        }
        _order.Enqueue(id);
        while (_order.Count > _capacity)
        {
            _ids.Remove(_order.Dequeue());
        }
        return true;
    }
}
