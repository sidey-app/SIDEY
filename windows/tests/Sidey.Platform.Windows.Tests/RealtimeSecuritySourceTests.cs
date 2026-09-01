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

    private static string Read(string name) => File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "TestAssets", name));
}
