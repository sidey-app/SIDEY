using Sidey.Core.Abstractions;
using Sidey.Core.Domain;

namespace Sidey.Presentation.Services;

public enum GroupOperation
{
    Idle,
    Creating,
    Joining,
    Switching,
    Mutating,
}

public sealed record CoordinatorState(
    Profile? Profile,
    IReadOnlyList<Room> Rooms,
    IReadOnlySet<string> ActiveEntitlementKeys,
    Guid? ActiveRoomId,
    IReadOnlyList<MessageLedgerEntry> Messages,
    AppPreferences Preferences,
    RealtimeConnectionStatus RealtimeConnection,
    IReadOnlyList<CommerceProductState> CommerceProducts,
    bool DevelopmentCommerceEnabled,
    GroupOperation GroupOperation,
    Guid? SwitchingRoomId,
    string? ErrorMessage)
{
    public bool Connected => RealtimeConnection.IsReady;

    public bool ActiveRoomConnected => RealtimeConnection.ActiveRoomTransportConnected;

    public static CoordinatorState Initial { get; } = new(
        null,
        [],
        new HashSet<string>(StringComparer.Ordinal),
        null,
        [],
        AppPreferences.Default,
        RealtimeConnectionStatus.Disconnected,
        WindowsCommerceCatalog.LockedStates(),
        false,
        GroupOperation.Idle,
        null,
        null);
}
