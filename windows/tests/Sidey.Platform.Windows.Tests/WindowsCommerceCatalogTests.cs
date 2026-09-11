using Sidey.Core.Domain;

namespace Sidey.Platform.Windows.Tests;

public sealed class WindowsCommerceCatalogTests
{
    [Fact]
    public void CandidateCatalogContainsTheTenApprovedProducts()
    {
        Assert.Equal(
            [
                "character_starlight_upalupa",
                "character_guinea_pig",
                "character_monkey",
                "character_chinchilla",
                "bubble_bunny_pink",
                "bubble_butter_chick",
                "bubble_starry_cat",
                "throwable_bouncy_heart",
                "throwable_toy_cannon",
                "throwable_squeaky_duck",
            ],
            WindowsCommerceCatalog.Products.Select(product => product.Id));
        Assert.Equal(
            [10, 20, 30, 40, 110, 120, 130, 210, 220, 230],
            WindowsCommerceCatalog.Products.Select(product => product.SortOrder));
        Assert.All(WindowsCommerceCatalog.Products, product => Assert.Equal(
            $"{product.Kind.ToString().ToLowerInvariant()}:{product.EffectiveCatalogItemId}",
            product.EntitlementKey));
    }

    [Fact]
    public void PubliclyLockedStateDoesNotExposePurchaseActions()
    {
        IReadOnlyList<CommerceProductState> states = WindowsCommerceCatalog.LockedStates();

        Assert.Equal(10, states.Count);
        Assert.All(states, state =>
        {
            Assert.False(state.GoogleConnected);
            Assert.False(state.IsWorking);
            Assert.Equal(CommercePurchaseState.Unavailable, state.PurchaseState);
        });
    }
}
