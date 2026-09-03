using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Sidey.Core.Overlay;

namespace Sidey.Core.Abstractions;

public sealed record AuthSession(
    Guid UserId,
    DateTimeOffset ExpiresAt);

public interface IAuthService
{
    Task<AuthSession?> RestoreSessionAsync(CancellationToken cancellationToken = default);
    Task<AuthSession> CreateAnonymousSessionAsync(CancellationToken cancellationToken = default);
    Task SignOutAsync(CancellationToken cancellationToken = default);
}

public sealed class SessionRecoveryException(string message, Exception? innerException = null)
    : Exception(message, innerException);

public static class AnonymousSessionBootstrapper
{
    public static async Task<AuthSession> RestoreOrCreateAsync(
        IAuthService auth,
        bool hasStoredSession,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(auth);
        AuthSession? restored;
        try
        {
            restored = await auth.RestoreSessionAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception exception) when (hasStoredSession)
        {
            throw new SessionRecoveryException(
                I18n.Get("auth.restoreFailed"),
                exception);
        }

        if (restored is not null)
        {
            return restored;
        }

        if (hasStoredSession)
        {
            throw new SessionRecoveryException(
                I18n.Get("auth.restoreFailed"));
        }

        return await auth.CreateAnonymousSessionAsync(cancellationToken).ConfigureAwait(false);
    }
}

public sealed record BackendSnapshot(
    Profile? Profile,
    IReadOnlyList<Room> Rooms,
    Guid CurrentUserId);

public sealed record CreateRoomResult(Room Room, string InviteCode);

public sealed record MessageHistoryCursor(DateTimeOffset CreatedAt, Guid Id);

public sealed record MessageHistoryPage(
    IReadOnlyList<ChatMessage> Messages,
    MessageHistoryCursor? NextCursor);

public abstract record BackendEvent
{
    public sealed record SnapshotReceived(BackendSnapshot Snapshot) : BackendEvent;
    public sealed record MessageReceived(ChatMessage Message) : BackendEvent;
    public sealed record MessageDeleted(Guid RoomId, Guid MessageId) : BackendEvent;
    public sealed record MessagesReplaced(Guid RoomId, IReadOnlyList<ChatMessage> Messages) : BackendEvent;
    public sealed record MessageChanged(Guid RoomId, Guid MessageId, string Operation) : BackendEvent;
    public sealed record MessagesInvalidated(Guid RoomId) : BackendEvent;
    public sealed record PresenceChanged(Guid RoomId, Guid UserId, PresenceState State) : BackendEvent;
    public sealed record TypingChanged(Guid RoomId, Guid UserId, bool Active) : BackendEvent;
    public sealed record CharacterPulsed(CharacterPulseEvent Pulse) : BackendEvent;
    public sealed record CharacterThrown(CharacterThrowEvent Throw) : BackendEvent;
    public sealed record RoomStructureChanged(Guid RoomId) : BackendEvent;
    public sealed record ConnectionChanged(bool Connected) : BackendEvent;
    public sealed record ReconciliationRequired : BackendEvent;
    public sealed record Diagnostic(string Stage) : BackendEvent;
    public sealed record TechnicalError(string Message) : BackendEvent;
}

public interface IBackendGateway
{
    Task<BackendSnapshot> FetchSnapshotAsync(CancellationToken cancellationToken = default);
    Task<Profile> SaveProfileAsync(string nickname, string characterId, CancellationToken cancellationToken = default);
    Task<CreateRoomResult> CreateRoomAsync(string name, CancellationToken cancellationToken = default);
    Task<Room> JoinRoomAsync(string inviteCode, CancellationToken cancellationToken = default);
    Task LeaveRoomAsync(Guid roomId, CancellationToken cancellationToken = default);
    Task RenameRoomAsync(Guid roomId, string name, CancellationToken cancellationToken = default);
    Task<string> RotateInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default);
    Task RemoveRoomMemberAsync(Guid roomId, Guid userId, CancellationToken cancellationToken = default);
    Task DeleteRoomAsync(Guid roomId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<ChatMessage>> FetchRecentMessagesAsync(Guid roomId, CancellationToken cancellationToken = default);
    Task<MessageHistoryPage> FetchMessagePageAsync(
        Guid roomId,
        MessageHistoryCursor? before,
        int limit = 50,
        CancellationToken cancellationToken = default);
    Task<ChatMessage> SendMessageAsync(Guid id, Guid roomId, string body, CancellationToken cancellationToken = default);
    Task PublishPresenceAsync(Guid roomId, PresenceState state, CancellationToken cancellationToken = default);
    Task BroadcastTypingAsync(Guid roomId, bool active, bool keepalive, CancellationToken cancellationToken = default);
    Task BroadcastCharacterPulseAsync(Guid roomId, Guid eventId, CancellationToken cancellationToken = default);
    Task BroadcastCharacterThrowAsync(
        Guid roomId,
        Guid eventId,
        Guid targetUserId,
        CancellationToken cancellationToken = default);
    Task SynchronizeRealtimeRoomsAsync(
        IReadOnlyDictionary<Guid, long> roomEpochs,
        Guid? activeRoomId,
        PresenceState localPresence,
        CancellationToken cancellationToken = default);
    IAsyncEnumerable<BackendEvent> SubscribeAsync(CancellationToken cancellationToken = default);
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
