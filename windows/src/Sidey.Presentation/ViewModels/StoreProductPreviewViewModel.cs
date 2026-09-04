namespace Sidey.Presentation.ViewModels;

public sealed record StoreProductPreviewViewModel(
    string CharacterId,
    string DisplayName,
    string Description,
    string FormattedPrice);
