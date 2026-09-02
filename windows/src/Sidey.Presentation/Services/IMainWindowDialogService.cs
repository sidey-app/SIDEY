namespace Sidey.Presentation.Services;

public interface IMainWindowDialogService
{
    Task<bool> ConfirmInviteCodeRotationAsync();

    Task<string?> PromptForRoomNameAsync(string currentName);

    Task<bool> ConfirmMemberRemovalAsync(string nickname);

    Task<bool> ConfirmRoomDeletionAsync(string roomName);

    Task<bool> ConfirmUpdateDownloadAsync(string version);
}
