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
        string characterId,
        bool isSelected,
        bool isEnabled,
        Func<Task> select)
    {
        Kind = kind;
        CatalogItemId = catalogItemId;
        DisplayName = displayName;
        CharacterId = characterId;
        IsSelected = isSelected;
        IsEnabled = isEnabled;
        SelectCommand = new AsyncRelayCommand(select);
    }

    public CommerceProductKind Kind { get; }
    public string? CatalogItemId { get; }
    [ObservableProperty]
    public partial string DisplayName { get; set; }
    public IAsyncRelayCommand SelectCommand { get; }

    [ObservableProperty]
    public partial string CharacterId { get; set; }

    [ObservableProperty]
    public partial bool IsSelected { get; set; }

    [ObservableProperty]
    public partial bool IsEnabled { get; set; }
}
