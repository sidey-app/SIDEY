using Sidey.Core.Abstractions;
using Sidey.Core.Domain;

namespace Sidey.Presentation.Services;

public interface ISideyCoordinator
{
    CoordinatorState State { get; }

    bool IsValidationMode { get; }

    string? ValidationMetricsPath { get; }

    ValidationMetricsSnapshot? ValidationMetricsSummary { get; }

    Task<MessageHistoryPage> FetchMessagePageAsync(
        Guid roomId,
        MessageHistoryCursor? before,
        int limit = 50,
        CancellationToken cancellationToken = default);

    Task SaveProfileAsync(
        string nickname,
        string characterId,
        CancellationToken cancellationToken = default);

    Task CreateRoomAsync(string name, CancellationToken cancellationToken = default);

    Task JoinRoomAsync(string inviteCode, CancellationToken cancellationToken = default);

    Task SwitchRoomAsync(Guid roomId, CancellationToken cancellationToken = default);

    Task RenameRoomAsync(
        Guid roomId,
        string name,
        CancellationToken cancellationToken = default);

    Task RotateInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default);

    Task RemoveRoomMemberAsync(
        Guid roomId,
        Guid userId,
        CancellationToken cancellationToken = default);

    Task DeleteRoomAsync(Guid roomId, CancellationToken cancellationToken = default);

    Task LeaveRoomAsync(Guid roomId, CancellationToken cancellationToken = default);

    Task<bool> CopyInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default);

    Task SetOverlayVisibleAsync(bool visible, CancellationToken cancellationToken = default);

    Task SetQuietModeAsync(bool enabled, CancellationToken cancellationToken = default);

    Task SetShowOfflineMembersAsync(
        bool enabled,
        CancellationToken cancellationToken = default);

    Task SetRequiresRightClickToThrowAsync(
        bool enabled,
        CancellationToken cancellationToken = default);

    Task SetStartAtLoginAsync(bool enabled, CancellationToken cancellationToken = default);

    Task SetRegionAsync(
        OverlayRegionPreference preference,
        CancellationToken cancellationToken = default);

    IReadOnlyList<MonitorOption> GetMonitors();

    void RequestComposer();

    Task<string?> ExportValidationMetricsAsync(CancellationToken cancellationToken = default);
}
