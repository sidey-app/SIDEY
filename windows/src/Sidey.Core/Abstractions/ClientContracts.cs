using Sidey.Core.Domain;
using Sidey.Core.Overlay;

namespace Sidey.Core.Abstractions;

public sealed record AuthSession(
    Guid UserId,
    DateTimeOffset ExpiresAt);

public interface IAuthService
{
    Task<Uri> BeginGooglePkceAsync(CancellationToken cancellationToken = default);
    Task<AuthSession> CompleteCallbackAsync(Uri callback, CancellationToken cancellationToken = default);
    Task<AuthSession?> RestoreSessionAsync(CancellationToken cancellationToken = default);
    Task SignOutAsync(CancellationToken cancellationToken = default);
}

public sealed record BackendSnapshot(
    Profile? Profile,
    IReadOnlyList<Room> Rooms,
    Guid CurrentUserId);

public sealed record CreateRoomResult(Room Room, string InviteCode);

public abstract record BackendEvent
{
    public sealed record MessageReceived(ChatMessage Message) : BackendEvent;
    public sealed record PresenceChanged(Guid RoomId, Guid UserId, PresenceState State) : BackendEvent;
    public sealed record TypingChanged(Guid RoomId, Guid UserId, bool Active) : BackendEvent;
    public sealed record CharacterPulsed(CharacterPulseEvent Pulse) : BackendEvent;
    public sealed record ConnectionChanged(bool Connected) : BackendEvent;
}

public interface IBackendGateway
{
    Task<BackendSnapshot> FetchSnapshotAsync(CancellationToken cancellationToken = default);
    Task<Profile> SaveProfileAsync(string nickname, string characterId, CancellationToken cancellationToken = default);
    Task<CreateRoomResult> CreateRoomAsync(string name, CancellationToken cancellationToken = default);
    Task<Room> JoinRoomAsync(string inviteCode, CancellationToken cancellationToken = default);
    Task LeaveRoomAsync(Guid roomId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<ChatMessage>> FetchRecentMessagesAsync(Guid roomId, CancellationToken cancellationToken = default);
    Task<ChatMessage> SendMessageAsync(Guid id, Guid roomId, string body, CancellationToken cancellationToken = default);
    Task PublishPresenceAsync(Guid roomId, PresenceState state, CancellationToken cancellationToken = default);
    Task BroadcastTypingAsync(Guid roomId, bool active, bool keepalive, CancellationToken cancellationToken = default);
    Task BroadcastCharacterPulseAsync(Guid roomId, Guid eventId, CancellationToken cancellationToken = default);
    IAsyncEnumerable<BackendEvent> SubscribeAsync(
        IReadOnlySet<Guid> roomIds,
        CancellationToken cancellationToken = default);
}

public interface IOverlayHost
{
    bool IsVisible { get; }
    ValueTask ApplyAsync(WorldSnapshot snapshot, CancellationToken cancellationToken = default);
    ValueTask SetVisibleAsync(bool visible, CancellationToken cancellationToken = default);
}

public interface IActivityMonitor : IAsyncDisposable
{
    IAsyncEnumerable<PresenceState> ObserveAsync(CancellationToken cancellationToken = default);
}

public interface IMonitorService
{
    IReadOnlyList<MonitorGeometry> GetMonitors();
}

public enum CredentialKey
{
    SupabaseSession,
    PendingPkceVerifier,
}

public interface ICredentialStore
{
    ValueTask<string?> ReadAsync(CredentialKey key, CancellationToken cancellationToken = default);
    ValueTask WriteAsync(CredentialKey key, string value, CancellationToken cancellationToken = default);
    ValueTask DeleteAsync(CredentialKey key, CancellationToken cancellationToken = default);
    ValueTask<string?> ReadInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default);
    ValueTask WriteInviteCodeAsync(Guid roomId, string inviteCode, CancellationToken cancellationToken = default);
    ValueTask DeleteInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default);
}

public interface IPreferencesStore
{
    ValueTask<AppPreferences> LoadAsync(CancellationToken cancellationToken = default);
    ValueTask SaveAsync(AppPreferences preferences, CancellationToken cancellationToken = default);
}
