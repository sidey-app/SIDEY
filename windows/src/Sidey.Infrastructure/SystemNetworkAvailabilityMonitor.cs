using System.Net.NetworkInformation;

namespace Sidey.Infrastructure;

internal interface INetworkAvailabilityMonitor : IDisposable
{
    bool IsAvailable { get; }

    event Action<bool>? AvailabilityChanged;

    void Start();
}

internal sealed class SystemNetworkAvailabilityMonitor : INetworkAvailabilityMonitor
{
    private int _available = NetworkInterface.GetIsNetworkAvailable() ? 1 : 0;
    private int _started;

    public bool IsAvailable => Volatile.Read(ref _available) != 0;

    public event Action<bool>? AvailabilityChanged;

    public void Start()
    {
        if (Interlocked.Exchange(ref _started, 1) != 0)
        {
            return;
        }

        NetworkChange.NetworkAvailabilityChanged += OnNetworkAvailabilityChanged;
        Update(NetworkInterface.GetIsNetworkAvailable());
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _started, 0) == 0)
        {
            return;
        }

        NetworkChange.NetworkAvailabilityChanged -= OnNetworkAvailabilityChanged;
    }

    private void OnNetworkAvailabilityChanged(object? sender, NetworkAvailabilityEventArgs args)
    {
        _ = sender;
        Update(args.IsAvailable);
    }

    private void Update(bool isAvailable)
    {
        int next = isAvailable ? 1 : 0;
        if (Interlocked.Exchange(ref _available, next) == next)
        {
            return;
        }

        AvailabilityChanged?.Invoke(isAvailable);
    }
}
