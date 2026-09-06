using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Sidey.Core.Domain;
using Sidey.Core.Localization;

namespace Sidey.Presentation.ViewModels;

public sealed partial class StoreProductPreviewViewModel : ObservableObject
{
    private readonly AsyncRelayCommand _actionCommand;

    public StoreProductPreviewViewModel(
        CommerceProduct product,
        string displayName,
        string description,
        string formattedPrice,
        Func<Task> action,
        Action preview)
    {
        ProductId = product.Id;
        CharacterId = product.CharacterId;
        Kind = product.Kind;
        CatalogItemId = product.EffectiveCatalogItemId;
        SortOrder = product.SortOrder;
        AmountKrw = product.AmountKrw;
        DisplayName = displayName;
        Description = description;
        FormattedPrice = formattedPrice;
        _actionCommand = new AsyncRelayCommand(action, () => IsActionEnabled);
        ActionCommand = _actionCommand;
        PreviewCommand = new RelayCommand(preview);
    }

    public string ProductId { get; }
    public string CharacterId { get; }
    public CommerceProductKind Kind { get; }
    public string CatalogItemId { get; }
    public int SortOrder { get; }
    public int AmountKrw { get; }
    public string DisplayName { get; }
    public string Description { get; }
    public string FormattedPrice { get; }
    public IAsyncRelayCommand ActionCommand { get; }
    public IRelayCommand PreviewCommand { get; }

    [ObservableProperty]
    public partial string ActionText { get; set; } = string.Empty;

    [ObservableProperty]
    public partial bool IsActionEnabled { get; set; }

    [ObservableProperty]
    public partial bool IsWorking { get; set; }

    [ObservableProperty]
    public partial bool IsPreviewOnlyVisible { get; set; } = true;

    [ObservableProperty]
    public partial bool IsOwned { get; set; }

    public void Apply(CommerceProductState state, bool commerceEnabled, bool isOwned)
    {
        IsPreviewOnlyVisible = !commerceEnabled;
        IsOwned = isOwned;
        IsWorking = state.IsWorking;
        IsActionEnabled = commerceEnabled
            && !state.IsWorking
            && state.PurchaseState is (
                CommercePurchaseState.GoogleConnectionRequired
                or CommercePurchaseState.Available
                or CommercePurchaseState.Refunded
                or CommercePurchaseState.Error);
        ActionText = state.PurchaseState switch
        {
            CommercePurchaseState.GoogleConnectionRequired => I18n.Get("store.connectGoogle"),
            CommercePurchaseState.Available or CommercePurchaseState.Refunded =>
                I18n.Format("store.purchase", FormattedPrice),
            CommercePurchaseState.OpeningCheckout => I18n.Get("store.openingCheckout"),
            CommercePurchaseState.Confirming => I18n.Get("store.confirming"),
            CommercePurchaseState.Owned => I18n.Get("store.owned"),
            CommercePurchaseState.Error => I18n.Get("store.retry"),
            _ => I18n.Get("store.comingSoon"),
        };
        _actionCommand.NotifyCanExecuteChanged();
    }
}
