using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Sidey.Core.Domain;

namespace Sidey.Presentation.ViewModels;

public sealed partial class CosmeticSelectionItemViewModel : ObservableObject
{
    public CosmeticSelectionItemViewModel(
        CommerceProductKind kind,
        string? catalogItemId,
        string displayName,
        bool isSelected,
        Func<Task> select)
    {
        Kind = kind;
        CatalogItemId = catalogItemId;
        DisplayName = displayName;
        IsSelected = isSelected;
        SelectCommand = new AsyncRelayCommand(select);
    }

    public CommerceProductKind Kind { get; }
    public string? CatalogItemId { get; }
    public string DisplayName { get; }
    public IAsyncRelayCommand SelectCommand { get; }

    [ObservableProperty]
    public partial bool IsSelected { get; set; }
}
