using Sidey.Core.Abstractions;
using Sidey.Core.Domain;

namespace Sidey.Presentation.Services;

public interface ICoordinatorStateSource
{
    public CoordinatorState State { get; }
}

public interface IHistoryCoordinator : ICoordinatorStateSource
{
    public Task<MessageHistoryPage> FetchMessagePageAsync(
        Guid roomId,
        MessageHistoryCursor? before,
        int limit = 50,
        CancellationToken cancellationToken = default);
}

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

public interface IMainWindowCoordinator : IOnboardingCoordinator
{
    public Task RetryConnectionAsync(bool userInitiated = true);
    public bool AnimationsEnabled { get; }
    public void ApplyCharacterSoundEffects(bool enabled, int volume);
    public Task SaveCharacterSoundEffectsAsync(bool enabled, int volume, CancellationToken cancellationToken = default);
    public void PlayImpactSound(string id, Guid scope, long requestedAt);
    public void StopImpactSounds(Guid? scope = null);
    public bool IsValidationMode { get; }

    public string? ValidationMetricsPath { get; }

    public ValidationMetricsSnapshot? ValidationMetricsSummary { get; }

    public Task SwitchRoomAsync(Guid roomId, CancellationToken cancellationToken = default);

    public Task RenameRoomAsync(
        Guid roomId,
        string name,
        CancellationToken cancellationToken = default);

    public Task RotateInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default);

    public Task RemoveRoomMemberAsync(
        Guid roomId,
        Guid userId,
        CancellationToken cancellationToken = default);

    public Task DeleteRoomAsync(Guid roomId, CancellationToken cancellationToken = default);

    public Task LeaveRoomAsync(Guid roomId, CancellationToken cancellationToken = default);

    public Task<bool> CopyInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default);

    public Task SetOverlayVisibleAsync(bool visible, CancellationToken cancellationToken = default);

    public Task SetQuietModeAsync(bool enabled, CancellationToken cancellationToken = default);

    public Task SetShowOfflineMembersAsync(
        bool enabled,
        CancellationToken cancellationToken = default);

    public Task SetRequiresRightClickToThrowAsync(
        bool enabled,
        CancellationToken cancellationToken = default);

    public Task SetStartAtLoginAsync(bool enabled, CancellationToken cancellationToken = default);

    public Task SetLanguageAsync(string language, CancellationToken cancellationToken = default);

    public Task SetRegionAsync(
        OverlayRegionPreference preference,
        CancellationToken cancellationToken = default);

    public Task ActivateStoreProductAsync(
        string productId,
        CancellationToken cancellationToken = default);

    public Task SetEquippedCosmeticAsync(
        CommerceProductKind kind,
        string? catalogItemId,
        CancellationToken cancellationToken = default);

    public Task CompleteGoogleIdentityLinkAsync(
        Uri callbackUri,
        CancellationToken cancellationToken = default);

    public IReadOnlyList<MonitorOption> GetMonitors();

    public void RequestComposer();

    public Task<string?> ExportValidationMetricsAsync(CancellationToken cancellationToken = default);
}

public interface ISideyCoordinator :
    IMainWindowCoordinator,
    IHistoryCoordinator
{
}
