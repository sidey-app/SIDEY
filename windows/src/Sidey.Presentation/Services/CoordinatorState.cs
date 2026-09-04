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
    bool Connected,
    GroupOperation GroupOperation,
    Guid? SwitchingRoomId,
    string? ErrorMessage)
{
    public static CoordinatorState Initial { get; } = new(
        null,
        [],
        new HashSet<string>(StringComparer.Ordinal),
        null,
        [],
        AppPreferences.Default,
        false,
        GroupOperation.Idle,
        null,
        null);
}
