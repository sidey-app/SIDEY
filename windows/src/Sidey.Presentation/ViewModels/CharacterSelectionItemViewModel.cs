using CommunityToolkit.Mvvm.ComponentModel;

namespace Sidey.Presentation.ViewModels;

public sealed partial class CharacterSelectionItemViewModel : ObservableObject
{
    public CharacterSelectionItemViewModel(string id, string displayName, string characterId)
    {
        Id = id;
        DisplayName = displayName;
        CharacterId = characterId;
    }

    public string Id { get; }

    public string DisplayName { get; }

    public string CharacterId { get; }

    [ObservableProperty]
    public partial bool IsSelected { get; set; }
}
