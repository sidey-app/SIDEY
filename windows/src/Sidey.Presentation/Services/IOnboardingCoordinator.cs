namespace Sidey.Presentation.Services;

public interface IOnboardingCoordinator : ICoordinatorStateSource
{
    public Task CompleteOnboardingAsync(CancellationToken cancellationToken = default);

    public Task SaveProfileAsync(
        string nickname,
        string characterId,
        CancellationToken cancellationToken = default);

    public Task CreateRoomAsync(string name, CancellationToken cancellationToken = default);

    public Task JoinRoomAsync(string inviteCode, CancellationToken cancellationToken = default);
}
