using Sidey.Core.Domain;

namespace Sidey.Presentation.Services;

public interface ICoordinatorStateSource
{
    public CoordinatorState State { get; }
}
