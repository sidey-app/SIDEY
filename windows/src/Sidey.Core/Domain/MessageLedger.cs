namespace Sidey.Core.Domain;

public enum MessageDeliveryState
{
    Pending,
    Confirmed,
}

public sealed record MessageLedgerEntry(
    Guid Id,
    Guid RoomId,
    Guid SenderId,
    string Body,
    DateTimeOffset CreatedAt,
    MessageDeliveryState State);

public sealed class MessageLedger
{
    private readonly List<MessageLedgerEntry> _entries = [];

    public IReadOnlyList<MessageLedgerEntry> Entries => _entries;

    public MessageLedgerEntry? Latest => _entries.LastOrDefault();

    public void Stage(
        Guid id,
        Guid roomId,
        Guid senderId,
        string body,
        DateTimeOffset? createdAt = null)
    {
        if (_entries.Any(entry => entry.Id == id))
        {
            return;
        }

        _entries.Add(new MessageLedgerEntry(
            id,
            roomId,
            senderId,
            body,
            createdAt ?? DateTimeOffset.UtcNow,
            MessageDeliveryState.Pending));
    }

    public bool Confirm(ChatMessage message)
    {
        var index = _entries.FindIndex(entry => entry.Id == message.Id);
        var wasKnown = index >= 0;
        var confirmed = new MessageLedgerEntry(
            message.Id,
            message.RoomId,
            message.SenderId,
            message.Body,
            message.CreatedAt,
            MessageDeliveryState.Confirmed);

        if (wasKnown)
        {
            _entries[index] = confirmed;
        }
        else
        {
            _entries.Add(confirmed);
        }

        SortEntries();
        return !wasKnown;
    }

    public void ReplaceConfirmed(Guid roomId, IEnumerable<ChatMessage> messages)
    {
        _entries.RemoveAll(entry => entry.RoomId == roomId && entry.State == MessageDeliveryState.Confirmed);
        foreach (var message in messages.Where(message => message.RoomId == roomId))
        {
            Confirm(message);
        }
    }

    public string? Fail(Guid id)
    {
        var index = _entries.FindIndex(entry => entry.Id == id && entry.State == MessageDeliveryState.Pending);
        if (index < 0)
        {
            return null;
        }

        var body = _entries[index].Body;
        _entries.RemoveAt(index);
        return body;
    }

    public MessageLedgerEntry? LatestIn(Guid roomId) =>
        _entries.LastOrDefault(entry => entry.RoomId == roomId);

    private void SortEntries() => _entries.Sort(static (left, right) =>
    {
        var dateComparison = left.CreatedAt.CompareTo(right.CreatedAt);
        return dateComparison != 0
            ? dateComparison
            : StringComparer.Ordinal.Compare(left.Id.ToString("D"), right.Id.ToString("D"));
    });
}

public sealed class ActiveBubbleLedger
{
    public const int MaximumVisible = 4;
    public static readonly TimeSpan DefaultLifetime = TimeSpan.FromSeconds(10);

    private readonly List<ActiveBubble> _bubbles = [];

    public IReadOnlyList<ActiveBubble> Bubbles => _bubbles;

    public void Show(
        Guid senderId,
        Guid messageId,
        string body,
        DateTimeOffset? expiresAt = null)
    {
        _bubbles.RemoveAll(bubble => bubble.SenderId == senderId || bubble.MessageId == messageId);
        _bubbles.Add(new ActiveBubble(
            senderId,
            messageId,
            body,
            expiresAt ?? DateTimeOffset.UtcNow.Add(DefaultLifetime)));
        _bubbles.Sort(static (left, right) =>
        {
            var dateComparison = left.ExpiresAt.CompareTo(right.ExpiresAt);
            return dateComparison != 0
                ? dateComparison
                : StringComparer.Ordinal.Compare(left.MessageId.ToString("D"), right.MessageId.ToString("D"));
        });

        if (_bubbles.Count > MaximumVisible)
        {
            _bubbles.RemoveRange(0, _bubbles.Count - MaximumVisible);
        }
    }

    public void Remove(Guid messageId) =>
        _bubbles.RemoveAll(bubble => bubble.MessageId == messageId);

    public void Clear() => _bubbles.Clear();

    public void Prune(DateTimeOffset? date = null)
    {
        var cutoff = date ?? DateTimeOffset.UtcNow;
        _bubbles.RemoveAll(bubble => bubble.ExpiresAt <= cutoff);
    }
}
