using Windows.UI.ViewManagement;

namespace Sidey.Platform.Windows.Windowing;

public sealed class WindowsAnimationSettings : IDisposable
{
    private readonly UISettings _settings = new();
    private volatile bool _enabled;
    public bool Enabled => _enabled;
    public event Action? Changed;

    public WindowsAnimationSettings()
    {
        _enabled = _settings.AnimationsEnabled;
        if (OperatingSystem.IsWindowsVersionAtLeast(10, 0, 19041))
            _settings.AnimationsEnabledChanged += OnChanged;
    }

    private void OnChanged(UISettings sender, UISettingsAnimationsEnabledChangedEventArgs args)
    {
        _enabled = sender.AnimationsEnabled;
        Changed?.Invoke();
    }

    public void Dispose()
    {
        if (OperatingSystem.IsWindowsVersionAtLeast(10, 0, 19041))
            _settings.AnimationsEnabledChanged -= OnChanged;
    }
}
