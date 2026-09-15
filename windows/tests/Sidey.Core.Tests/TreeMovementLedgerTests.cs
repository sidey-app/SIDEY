using Sidey.Core.Domain;
using Sidey.Core.Overlay;

namespace Sidey.Core.Tests;

public sealed class TreeMovementLedgerTests
{
    [Fact]
    public void LateSnapshotAndRpcCannotReverseANewerConfirmedState()
    {
        var ledger = new TreeMovementLedger();
        var user = Guid.NewGuid();
        Assert.Equal((true, (long?)2), ledger.Merge(user, true, 2));
        Assert.Equal((false, (long?)3), ledger.Merge(user, false, 3));
        Assert.Equal((false, (long?)3), ledger.Merge(user, true, 2));
        Assert.Equal((false, (long?)3), ledger.Merge(user, true, null));
        Assert.Equal((false, (long?)3), ledger.Merge(user, true, 3));
    }

    [Fact]
    public void PeersRemainIndependentAndAccountResetDropsOldRevisions()
    {
        var ledger = new TreeMovementLedger();
        Guid first = Guid.NewGuid(), second = Guid.NewGuid();
        ledger.Merge(first, true, 12);
        Assert.Equal((false, (long?)0), ledger.Merge(second, false, 0));
        Assert.Equal((true, (long?)12), ledger.Merge(first, false, 0));
        ledger.Clear();
        Assert.Equal((false, (long?)0), ledger.Merge(first, false, 0));
    }

    [Fact]
    public void MissingBackendFieldDoesNotLookLikeAnUninitializedServer()
    {
        var ledger = new TreeMovementLedger();
        var user = Guid.NewGuid();
        Assert.Null(ledger.Merge(user, false, null).Revision);
        Assert.Equal(0, ledger.Merge(user, false, 0).Revision);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void EachTreesServerValueControlsMovementForLocalAndRemoteMembers(bool currentUser)
    {
        var tree = new PixelWorldMember(Guid.NewGuid(), "Tree", "pixel_tree",
            PresenceState.Online, false, currentUser, TreeMovementPaused: true, TreeMovementRevision: 7);
        Assert.True(PixelMovementPolicy.IsTreePaused(tree, false));
        Assert.False(PixelMovementPolicy.IsTreePaused(tree with { TreeMovementPaused = false }, false));
        Assert.False(PixelMovementPolicy.IsTreePaused(tree with { CharacterId = "pixel_otter" }, false));
    }

    [Theory]
    [InlineData(null)]
    [InlineData(0L)]
    public void UninitializedAndOldBackendsKeepLocalPauseWithoutPausingPeers(long? revision)
    {
        var tree = new PixelWorldMember(Guid.NewGuid(), "Tree", "pixel_tree",
            PresenceState.Online, false, true, TreeMovementRevision: revision);
        Assert.True(PixelMovementPolicy.IsTreePaused(tree, true));
        Assert.False(PixelMovementPolicy.IsTreePaused(tree, false));
        Assert.False(PixelMovementPolicy.IsTreePaused(tree with { IsCurrentUser = false }, true));
        Assert.False(PixelMovementPolicy.IsTreePaused(tree with { TreeMovementRevision = 1 }, true));
    }
}
