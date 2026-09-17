using CommunityToolkit.Mvvm.Input;

namespace Sidey.Presentation.ViewModels;

public sealed record HistoryEntryViewModel(
    Guid Id,
    string SenderName,
    string Body,
    string LocalTimeText,
    string CharacterId,
    bool IsCurrentUser,
    bool IsPending,
    bool IsFailed,
    DateTimeOffset CreatedAt,
    IAsyncRelayCommand? RetryCommand = null)
{
    public bool CanRetry => IsFailed && IsCurrentUser && RetryCommand is not null;
}
