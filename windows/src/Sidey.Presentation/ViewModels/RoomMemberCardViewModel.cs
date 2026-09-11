using CommunityToolkit.Mvvm.Input;

namespace Sidey.Presentation.ViewModels;

public sealed record RoomMemberCardViewModel(
    Guid RoomId,
    Guid UserId,
    string Nickname,
    string CharacterId,
    bool IsOwner,
    bool IsCurrentUser,
    bool CanRemove,
    IAsyncRelayCommand RemoveCommand);
