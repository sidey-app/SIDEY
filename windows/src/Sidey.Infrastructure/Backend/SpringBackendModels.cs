using System.Text.Json.Serialization;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Core.Localization;

namespace Sidey.Infrastructure.Backend;

internal sealed record SpringMember(Guid UserId, Profile? Profile);
internal sealed record SpringRoom(Guid Id, string Name, Guid OwnerId, string InviteCodeHint,
    long InviteVersion, IReadOnlyList<SpringMember> Members)
{
    internal Room Domain => new(Id, Name, OwnerId,
        [.. Members.Select(member => new RoomMember(member.UserId,
            member.Profile?.Nickname ?? I18n.Get("common.friend"),
            PixelCharacterCatalog.NormalizeId(member.Profile?.CharacterId), PresenceState.Offline,
            member.Profile?.EquippedBubbleStyleId, member.Profile?.TreeMovementPaused ?? false,
            member.Profile?.TreeMovementRevision))], InviteCodeHint, true);
}

internal sealed record SpringCreatedRoom(SpringRoom Room, string InviteCode);
internal sealed record SpringCheckout(Guid OrderId, Uri CheckoutUrl);
internal sealed record SpringMessageAck(ChatMessage Message);
internal sealed record SpringSubscribeAck(MessageHistoryCursor? RecoveryThrough);
internal sealed record SpringEntitlement(
    [property: JsonPropertyName("entitlement_key")] string EntitlementKey, string Status);
internal sealed record SpringCatalogProduct(string Id,
    [property: JsonPropertyName("product_kind")] string ProductKind,
    [property: JsonPropertyName("catalog_item_id")] string CatalogItemId,
    [property: JsonPropertyName("character_id")] string? CharacterId,
    [property: JsonPropertyName("entitlement_key")] string EntitlementKey,
    [property: JsonPropertyName("sort_order")] int SortOrder,
    [property: JsonPropertyName("amount_krw")] int AmountKrw,
    string Currency,
    [property: JsonPropertyName("tax_inclusive")] bool TaxInclusive);

/// Bounded UI cache; complete older history remains cursor-paged in PostgreSQL.
/// Live maxima never advance the completed REST recovery checkpoint.
internal sealed class SpringMessageLedger(int capacity = 1000)
{
    private readonly Dictionary<Guid, ChatMessage> _messages = [];
    internal MessageHistoryCursor? ConfirmedCursor { get; private set; }
    internal IReadOnlyList<ChatMessage> Messages => [.. _messages.Values
        .OrderBy(message => message.CreatedAt)
        .ThenBy(message => message.Id.ToString("D"), StringComparer.Ordinal)];

    internal bool Merge(ChatMessage message)
    {
        bool added = !_messages.ContainsKey(message.Id);
        _messages[message.Id] = message;
        foreach (ChatMessage old in Messages.Take(Math.Max(0, _messages.Count - Math.Max(1, capacity))))
        {
            _messages.Remove(old.Id);
        }
        return added;
    }

    internal void CompleteRecovery(MessageHistoryCursor through)
    {
        ConfirmedCursor = through;
    }

    internal void Prune(DateTimeOffset now)
    {
        foreach (Guid id in _messages.Values.Where(message => message.CreatedAt < now.AddDays(-3))
            .Select(message => message.Id).ToArray())
        {
            _messages.Remove(id);
        }
    }
}
