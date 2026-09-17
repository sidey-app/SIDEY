using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Infrastructure.Authentication;
using Sidey.Infrastructure.Backend;
using Sidey.Infrastructure.Configuration;

namespace Sidey.Infrastructure.ContractTests;

public sealed class SpringCommerceCatalogTests
{
    [Fact]
    public async Task PartialCatalogPreservesOwnedEquipmentAndDisablesOnlyMissingPurchases()
    {
        await using var fixture = new Fixture();
        CommerceProduct available = WindowsCommerceCatalog.Products[0];
        CommerceProduct refunded = WindowsCommerceCatalog.Products[1];
        CommerceProduct owned = WindowsCommerceCatalog.Products.Single(product => product.Id == "bubble_bunny_pink");
        fixture.Catalog = [Row(available)];
        fixture.Entitlements = [Entitlement(owned, "active"), Entitlement(refunded, "refunded")];
        fixture.Profile = fixture.Profile with { EquippedBubbleStyleId = owned.EffectiveCatalogItemId };

        IReadOnlyList<CommerceProductState> states = await fixture.Gateway.GetWindowsCommerceStateAsync();

        Assert.Equal(WindowsCommerceCatalog.Products.Count, states.Count);
        Assert.Equal(CommercePurchaseState.Available, states.Single(value => value.Product.Id == available.Id).PurchaseState);
        Assert.Equal(CommercePurchaseState.Owned, states.Single(value => value.Product.Id == owned.Id).PurchaseState);
        Assert.Equal(CommercePurchaseState.Unavailable, states.Single(value => value.Product.Id == refunded.Id).PurchaseState);
        Assert.All(states.Where(value => value.Product.Id != available.Id && value.Product.Id != owned.Id),
            value => Assert.Equal(CommercePurchaseState.Unavailable, value.PurchaseState));
        BackendSnapshot snapshot = await fixture.Gateway.FetchSnapshotAsync();
        Assert.Contains(owned.EntitlementKey, snapshot.ActiveEntitlementKeys);
        Assert.Equal(owned.EffectiveCatalogItemId, snapshot.Profile!.EquippedBubbleStyleId);
        Assert.All(fixture.Methods, method => Assert.Equal(HttpMethod.Get, method));
    }

    [Fact]
    public async Task EmptyCatalogIsValidAndDoesNotEraseActiveEntitlements()
    {
        await using var fixture = new Fixture();
        CommerceProduct owned = WindowsCommerceCatalog.Products[0];
        fixture.Entitlements = [Entitlement(owned, "active")];
        IReadOnlyList<CommerceProductState> states = await fixture.Gateway.GetWindowsCommerceStateAsync();
        Assert.Equal(CommercePurchaseState.Owned, states.Single(value => value.Product.Id == owned.Id).PurchaseState);
        Assert.All(states.Where(value => value.Product.Id != owned.Id),
            value => Assert.Equal(CommercePurchaseState.Unavailable, value.PurchaseState));
    }

    [Fact]
    public async Task DuplicateKnownProductIsRejected()
    {
        await using var fixture = new Fixture();
        CommerceProduct product = WindowsCommerceCatalog.Products[0];
        fixture.Catalog = [Row(product), Row(product)];
        await Assert.ThrowsAsync<InvalidOperationException>(() => fixture.Gateway.GetWindowsCommerceStateAsync());
    }

    [Theory]
    [InlineData("catalog_item_id")]
    [InlineData("entitlement_key")]
    [InlineData("product_kind")]
    [InlineData("currency")]
    public async Task KnownProductMetadataMismatchIsRejected(string field)
    {
        await using var fixture = new Fixture();
        Dictionary<string, object?> row = Row(WindowsCommerceCatalog.Products[0]);
        row[field] = "mismatched";
        fixture.Catalog = [row];
        await Assert.ThrowsAsync<InvalidDataException>(() => fixture.Gateway.GetWindowsCommerceStateAsync());
    }

    [Fact]
    public async Task FutureUnknownProductDoesNotInvalidateKnownCatalog()
    {
        await using var fixture = new Fixture();
        CommerceProduct known = WindowsCommerceCatalog.Products[0];
        Dictionary<string, object?> future = Row(known);
        future["id"] = "future_product";
        future["entitlement_key"] = "future:unknown";
        fixture.Catalog = [Row(known), future];
        IReadOnlyList<CommerceProductState> states = await fixture.Gateway.GetWindowsCommerceStateAsync();
        Assert.Equal(WindowsCommerceCatalog.Products.Count, states.Count);
        Assert.Equal(CommercePurchaseState.Available, states.Single(value => value.Product.Id == known.Id).PurchaseState);
        Assert.DoesNotContain(states, value => value.Product.Id == "future_product");
    }

    private static Dictionary<string, object?> Row(CommerceProduct product) => new()
    {
        ["id"] = product.Id,
        ["product_kind"] = product.Kind.ToString().ToLowerInvariant(),
        ["catalog_item_id"] = product.EffectiveCatalogItemId,
        ["character_id"] = product.Kind == CommerceProductKind.Character ? product.CharacterId : null,
        ["entitlement_key"] = product.EntitlementKey,
        ["sort_order"] = product.SortOrder,
        ["amount_krw"] = product.AmountKrw,
        ["currency"] = "KRW",
        ["tax_inclusive"] = true,
    };

    private static object Entitlement(CommerceProduct product, string status) => new
    {
        entitlement_key = product.EntitlementKey,
        status,
    };

    private sealed class Fixture : HttpMessageHandler, ICredentialStore, IAsyncDisposable
    {
        private static readonly JsonSerializerOptions s_json = new(JsonSerializerDefaults.Web);
        private readonly HttpClient _http;
        private readonly SideyAuthService _auth;
        private readonly string _session;
        public SpringBackendGateway Gateway { get; }
        public Profile Profile { get; set; } = new(Guid.NewGuid(), "Owned", "pixel_hamster");
        public object[] Catalog { get; set; } = [];
        public object[] Entitlements { get; set; } = [];
        public List<HttpMethod> Methods { get; } = [];

        public Fixture()
        {
            var configuration = new SideyRuntimeConfiguration(new Uri("https://catalog.test/api"));
            _session = JsonSerializer.Serialize(new SideySession(Profile.Id, Guid.NewGuid(), "access", "refresh",
                DateTimeOffset.UtcNow.AddMinutes(15)), s_json);
            _http = new HttpClient(this);
            _auth = new SideyAuthService(configuration, this, _http);
            Gateway = new SpringBackendGateway(configuration, _auth, this);
        }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Assert.Equal("Bearer", request.Headers.Authorization?.Scheme);
            Methods.Add(request.Method);
            object payload = request.RequestUri!.AbsolutePath switch
            {
                "/api/commerce/catalog" => Catalog,
                "/api/commerce/entitlements" => Entitlements,
                "/api/profile" => Profile,
                "/api/rooms" => Array.Empty<object>(),
                _ => throw new InvalidOperationException("Unexpected request in catalog fixture."),
            };
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(payload, options: s_json) });
        }

        public ValueTask<string?> ReadAsync(CredentialKey key, CancellationToken cancellationToken = default) =>
            ValueTask.FromResult(key == CredentialKey.SideySession ? _session : null);
        public ValueTask WriteAsync(CredentialKey key, string value, CancellationToken cancellationToken = default) =>
            throw new InvalidOperationException("Reading the catalog must not write credentials.");
        public ValueTask DeleteAsync(CredentialKey key, CancellationToken cancellationToken = default) =>
            throw new InvalidOperationException("Reading the catalog must not delete credentials.");
        public ValueTask<string?> ReadInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default) => ValueTask.FromResult<string?>(null);
        public ValueTask WriteInviteCodeAsync(Guid roomId, string inviteCode, CancellationToken cancellationToken = default) => ValueTask.CompletedTask;
        public ValueTask DeleteInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default) => ValueTask.CompletedTask;

        public async ValueTask DisposeAsync()
        {
            await Gateway.DisposeAsync();
            _auth.Dispose();
            _http.Dispose();
        }
    }
}
