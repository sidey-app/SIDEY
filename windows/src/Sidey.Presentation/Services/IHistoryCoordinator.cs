using Sidey.Core.Abstractions;

namespace Sidey.Presentation.Services;

public interface IHistoryCoordinator : ICoordinatorStateSource
{
    public Task<MessageHistoryPage> FetchMessagePageAsync(
        Guid roomId,
        MessageHistoryCursor? before,
        int limit = 50,
        CancellationToken cancellationToken = default);
}
