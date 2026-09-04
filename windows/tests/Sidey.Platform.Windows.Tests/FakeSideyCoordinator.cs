using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Presentation.Services;

namespace Sidey.Platform.Windows.Tests;

internal sealed class FakeSideyCoordinator : ISideyCoordinator
{
    public CoordinatorState State { get; set; } = CoordinatorState.Initial;

    public IReadOnlyList<ChatMessage> MessagePage { get; set; } = [];

    public MessageHistoryCursor? NextMessageCursor { get; set; }

    public Func<Guid, MessageHistoryCursor?, int, CancellationToken, Task<MessageHistoryPage>>?
        MessagePageLoader
    { get; set; }

    public bool IsValidationMode => false;

    public string? ValidationMetricsPath => null;

    public ValidationMetricsSnapshot? ValidationMetricsSummary => null;

    public IReadOnlyList<MonitorOption> Monitors { get; set; } = [];

    public int SaveProfileCallCount { get; private set; }

    public Func<string, string, CancellationToken, Task>? SaveProfileHandler { get; set; }

    public int CreateRoomCallCount { get; private set; }

    public Func<string, CancellationToken, Task>? CreateRoomHandler { get; set; }

    public int JoinRoomCallCount { get; private set; }

    public Func<string, CancellationToken, Task>? JoinRoomHandler { get; set; }

    public int SwitchRoomCallCount { get; private set; }

    public int RemoveRoomMemberCallCount { get; private set; }

    public int DeleteRoomCallCount { get; private set; }

    public int LeaveRoomCallCount { get; private set; }

    public Guid? LastLeftRoomId { get; private set; }

    public Task<MessageHistoryPage> FetchMessagePageAsync(
        Guid roomId,
        MessageHistoryCursor? before,
        int limit = 50,
        CancellationToken cancellationToken = default) => MessagePageLoader is { } loader
            ? loader(roomId, before, limit, cancellationToken)
            : Task.FromResult(new MessageHistoryPage(MessagePage, NextMessageCursor));

    public Task SaveProfileAsync(
        string nickname,
        string characterId,
        CancellationToken cancellationToken = default)
    {
        SaveProfileCallCount++;
        return SaveProfileHandler?.Invoke(nickname, characterId, cancellationToken)
            ?? Task.CompletedTask;
    }

    public Task CreateRoomAsync(string name, CancellationToken cancellationToken = default)
    {
        CreateRoomCallCount++;
        return CreateRoomHandler?.Invoke(name, cancellationToken) ?? Task.CompletedTask;
    }

    public Task JoinRoomAsync(string inviteCode, CancellationToken cancellationToken = default)
    {
        JoinRoomCallCount++;
        return JoinRoomHandler?.Invoke(inviteCode, cancellationToken) ?? Task.CompletedTask;
    }

    public Task SwitchRoomAsync(Guid roomId, CancellationToken cancellationToken = default)
    {
        SwitchRoomCallCount++;
        return Task.CompletedTask;
    }

    public Task RenameRoomAsync(
        Guid roomId,
        string name,
        CancellationToken cancellationToken = default) => Task.CompletedTask;

    public Task RotateInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default) =>
        Task.CompletedTask;

    public Task RemoveRoomMemberAsync(
        Guid roomId,
        Guid userId,
        CancellationToken cancellationToken = default)
    {
        RemoveRoomMemberCallCount++;
        return Task.CompletedTask;
    }

    public Task DeleteRoomAsync(Guid roomId, CancellationToken cancellationToken = default)
    {
        DeleteRoomCallCount++;
        return Task.CompletedTask;
    }

    public Task LeaveRoomAsync(Guid roomId, CancellationToken cancellationToken = default)
    {
        LeaveRoomCallCount++;
        LastLeftRoomId = roomId;
        return Task.CompletedTask;
    }

    public Task<bool> CopyInviteCodeAsync(Guid roomId, CancellationToken cancellationToken = default) =>
        Task.FromResult(true);

    public Task SetOverlayVisibleAsync(bool visible, CancellationToken cancellationToken = default) =>
        Task.CompletedTask;

    public Task SetQuietModeAsync(bool enabled, CancellationToken cancellationToken = default) =>
        Task.CompletedTask;

    public Task SetShowOfflineMembersAsync(
        bool enabled,
        CancellationToken cancellationToken = default) => Task.CompletedTask;

    public Task SetRequiresRightClickToThrowAsync(
        bool enabled,
        CancellationToken cancellationToken = default) => Task.CompletedTask;

    public Task SetStartAtLoginAsync(bool enabled, CancellationToken cancellationToken = default) =>
        Task.CompletedTask;

    public Task SetRegionAsync(
        OverlayRegionPreference preference,
        CancellationToken cancellationToken = default) => Task.CompletedTask;

    public IReadOnlyList<MonitorOption> GetMonitors() => Monitors;

    public void RequestComposer()
    {
    }

    public Task<string?> ExportValidationMetricsAsync(CancellationToken cancellationToken = default) =>
        Task.FromResult<string?>(null);
}

internal sealed class FakeMainWindowDialogService : IMainWindowDialogService
{
    public bool ConfirmUpdateDownload { get; set; } = true;

    public bool ConfirmMemberRemoval { get; set; } = true;

    public bool ConfirmRoomDeletion { get; set; } = true;

    public bool ConfirmRoomLeave { get; set; } = true;

    public string? ConfirmedRemovalNickname { get; private set; }

    public string? ConfirmedLeaveRoomName { get; private set; }

    public bool? ConfirmedLeaveRoomIsOwner { get; private set; }

    public Task<bool> ConfirmInviteCodeRotationAsync() => Task.FromResult(true);

    public Task<string?> PromptForRoomNameAsync(string currentName) =>
        Task.FromResult<string?>(currentName);

    public Task<bool> ConfirmMemberRemovalAsync(string nickname)
    {
        ConfirmedRemovalNickname = nickname;
        return Task.FromResult(ConfirmMemberRemoval);
    }

    public Task<bool> ConfirmRoomDeletionAsync(string roomName) =>
        Task.FromResult(ConfirmRoomDeletion);

    public Task<bool> ConfirmRoomLeaveAsync(string roomName, bool isOwner)
    {
        ConfirmedLeaveRoomName = roomName;
        ConfirmedLeaveRoomIsOwner = isOwner;
        return Task.FromResult(ConfirmRoomLeave);
    }

    public Task<bool> ConfirmUpdateDownloadAsync(string version)
    {
        _ = version;
        return Task.FromResult(ConfirmUpdateDownload);
    }
}

internal sealed class FakeUpdateService : IUpdateService
{
    public string CurrentVersion { get; set; } = "1.0.6";

    public DateTimeOffset? LastCheckedAt { get; set; }

    public Uri CurrentReleaseNotesUri { get; set; } = new(
        "https://github.com/sidey-app/SIDEY/releases/tag/windows-v1.0.6");

    public AvailableUpdate? AvailableUpdate { get; set; }

    public int InstallerLaunchCount { get; private set; }

    public int ReleaseNotesLaunchCount { get; private set; }

    public Task<AvailableUpdate?> CheckAsync(CancellationToken cancellationToken = default)
    {
        LastCheckedAt = DateTimeOffset.UtcNow;
        return Task.FromResult(AvailableUpdate);
    }

    public Task DownloadAndLaunchInstallerAsync(
        AvailableUpdate update,
        CancellationToken cancellationToken = default)
    {
        _ = update;
        _ = cancellationToken;
        InstallerLaunchCount++;
        return Task.CompletedTask;
    }

    public Task OpenReleaseNotesAsync(Uri releaseNotesUri)
    {
        _ = releaseNotesUri;
        ReleaseNotesLaunchCount++;
        return Task.CompletedTask;
    }
}
