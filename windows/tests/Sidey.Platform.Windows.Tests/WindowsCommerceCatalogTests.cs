using Sidey.Core.Domain;

namespace Sidey.Platform.Windows.Tests;

public sealed class WindowsCommerceCatalogTests
{
    [Fact]
    public void CandidateCatalogContainsOnlyTheFourApprovedCharacterProducts()
    {
        Assert.Equal(
            [
                "character_starlight_upalupa",
                "character_guinea_pig",
                "character_monkey",
                "character_chinchilla",
            ],
            WindowsCommerceCatalog.Products.Select(product => product.Id));
        Assert.Equal(
            [10, 20, 30, 40],
            WindowsCommerceCatalog.Products.Select(product => product.SortOrder));
        Assert.All(WindowsCommerceCatalog.Products, product =>
            Assert.Equal($"character:{product.CharacterId}", product.EntitlementKey));
    }

    [Fact]
    public void PubliclyLockedStateDoesNotExposePurchaseActions()
    {
        IReadOnlyList<CommerceProductState> states = WindowsCommerceCatalog.LockedStates();

        Assert.Equal(4, states.Count);
        Assert.All(states, state =>
        {
            Assert.False(state.GoogleConnected);
            Assert.False(state.IsWorking);
            Assert.Equal(CommercePurchaseState.Unavailable, state.PurchaseState);
        });
    }
}
