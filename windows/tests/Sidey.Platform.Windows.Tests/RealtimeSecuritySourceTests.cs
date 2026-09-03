namespace Sidey.Platform.Windows.Tests;

public sealed class RealtimeSecuritySourceTests
{
    [Fact]
    public void TransientEventsUseValidatedRpcInsteadOfClientBroadcast()
    {
        var gateway = Read("SupabaseBackendGateway.cs");
        var transport = Read("SupabaseRealtimeTransport.cs");

        Assert.Contains("\"broadcast_room_event\"", gateway, StringComparison.Ordinal);
        Assert.Contains("p_realtime_epoch", gateway, StringComparison.Ordinal);
        Assert.DoesNotContain("SendBroadcastAsync", transport, StringComparison.Ordinal);
        Assert.DoesNotContain("BroadcastTypingAsync", transport, StringComparison.Ordinal);
        Assert.DoesNotContain("BroadcastCharacterPulseAsync", transport, StringComparison.Ordinal);
        Assert.Contains("\"broadcast_character_throw\"", gateway, StringComparison.Ordinal);
        Assert.Contains("p_target_user_id", gateway, StringComparison.Ordinal);
        Assert.DoesNotContain("BroadcastCharacterThrowAsync", transport, StringComparison.Ordinal);
    }

    [Fact]
    public void DatabaseBroadcastNeverConstructsMessageFromPayloadBody()
    {
        var gateway = Read("SupabaseBackendGateway.cs");
        var transport = Read("SupabaseRealtimeTransport.cs");

        Assert.Contains("message_changed", transport, StringComparison.Ordinal);
        Assert.Contains("messages_pruned", transport, StringComparison.Ordinal);
        Assert.DoesNotContain("body.GetString", transport, StringComparison.Ordinal);
        Assert.Contains("room_id=eq.", gateway, StringComparison.Ordinal);
        Assert.Contains("id=eq.", gateway, StringComparison.Ordinal);
    }

    [Fact]
    public void RealtimeStreamIsBoundedAndOverflowForcesReconciliation()
    {
        var gateway = Read("SupabaseBackendGateway.cs");
        var transport = Read("SupabaseRealtimeTransport.cs");

        Assert.Contains("CreateBounded<BackendEvent>", transport, StringComparison.Ordinal);
        Assert.Contains("ReconciliationRequired", transport, StringComparison.Ordinal);
        Assert.Contains("EmitReconciliationWithRetryAsync", gateway, StringComparison.Ordinal);
    }

    [Fact]
    public void InitialWebSocketFailureStartsRecoveryWithoutAbortingInitialization()
    {
        var transport = Read("SupabaseRealtimeTransport.cs");

        Assert.Contains("catch (WebSocketException exception)", transport, StringComparison.Ordinal);
        Assert.Contains("_ = RecoverAsync();", transport, StringComparison.Ordinal);
        Assert.Contains("socket.Dispose();", transport, StringComparison.Ordinal);
    }

    [Fact]
    public void PresenceSubscriptionExplicitlyRequestsRemoteState()
    {
        var transport = Read("SupabaseRealtimeTransport.cs");

        Assert.Contains("enabled = true", transport, StringComparison.Ordinal);
        Assert.Contains("join_ref = joinReference", transport, StringComparison.Ordinal);
        Assert.Contains("_joinReferences[descriptor.PhoenixTopic] = reference", transport, StringComparison.Ordinal);
        Assert.Contains("presence_state", transport, StringComparison.Ordinal);
        Assert.Contains("presence_diff", transport, StringComparison.Ordinal);
    }

    [Fact]
    public void WebSocketUpgradeUsesQueryAuthenticationAndHttp11()
    {
        var transport = Read("SupabaseRealtimeTransport.cs");

        Assert.Contains("HttpVersion.Version11", transport, StringComparison.Ordinal);
        Assert.Contains("HttpVersionPolicy.RequestVersionExact", transport, StringComparison.Ordinal);
        Assert.Contains("Query = $\"apikey=", transport, StringComparison.Ordinal);
        Assert.DoesNotContain("SetRequestHeader(\"Authorization\"", transport, StringComparison.Ordinal);
        Assert.DoesNotContain("SetRequestHeader(\"apikey\"", transport, StringComparison.Ordinal);
        Assert.Contains("access_token = session.AccessToken", transport, StringComparison.Ordinal);
    }

    [Fact]
    public void FirstActiveRoomWaitsForRealtimeConnectionBeforeStartingOverlay()
    {
        var coordinator = Read("AppCoordinator.cs");
        var reconcileStart = coordinator.IndexOf(
            "private async Task ReconcileSnapshotAsync",
            StringComparison.Ordinal);
        var reconcileEnd = coordinator.IndexOf(
            "private async Task RefreshSnapshotAndSelectAsync",
            reconcileStart,
            StringComparison.Ordinal);
        var reconcile = coordinator[reconcileStart..reconcileEnd];

        var overlayStart = reconcile.IndexOf("StartOverlay(CurrentWorldSnapshot());", StringComparison.Ordinal);
        var realtimeSync = reconcile.IndexOf("SynchronizeRealtimeRoomsAsync", StringComparison.Ordinal);
        Assert.True(overlayStart >= 0, "Reconciliation must start an overlay for the first active room.");
        Assert.True(realtimeSync >= 0, "Reconciliation must synchronize Realtime state.");
        Assert.True(overlayStart > realtimeSync, "Overlay startup must wait for Realtime synchronization.");
        Assert.Contains("&& _state.Connected", reconcile, StringComparison.Ordinal);

        var connectionStart = coordinator.IndexOf(
            "private void SetRealtimeConnected(bool connected)",
            StringComparison.Ordinal);
        var connectionEnd = coordinator.IndexOf(
            "private void ApplySnapshot",
            connectionStart,
            StringComparison.Ordinal);
        var connection = coordinator[connectionStart..connectionEnd];
        Assert.Contains("StartOverlay(CurrentWorldSnapshot());", connection, StringComparison.Ordinal);
    }

    [Fact]
    public void StartupSeedsCachedActiveRoomBeforePublishingFirstSnapshot()
    {
        var coordinator = Read("AppCoordinator.cs");
        var initializeStart = coordinator.IndexOf(
            "public async Task InitializeAsync",
            StringComparison.Ordinal);
        var initializeEnd = coordinator.IndexOf(
            "public async Task SaveProfileAsync",
            initializeStart,
            StringComparison.Ordinal);
        var initialize = coordinator[initializeStart..initializeEnd];

        var loadPreferences = initialize.IndexOf(
            "await LoadCachedStateAsync(cancellationToken);",
            StringComparison.Ordinal);
        var selectCachedRoom = initialize.IndexOf(
            "SelectActiveRoom(preferences.ActiveRoomId, snapshot.Rooms)",
            StringComparison.Ordinal);
        var publishSnapshot = initialize.IndexOf("ApplySnapshot(snapshot);", StringComparison.Ordinal);

        Assert.True(loadPreferences >= 0, "Cached settings must load before network startup.");
        Assert.True(selectCachedRoom > loadPreferences, "The cached room must be selected after rooms load.");
        Assert.True(
            publishSnapshot > selectCachedRoom,
            "The first room snapshot must already contain the cached active room.");
    }

    private static string Read(string name) => File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "TestAssets", name));
}
