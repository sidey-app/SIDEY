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
    DateTimeOffset CreatedAt);
