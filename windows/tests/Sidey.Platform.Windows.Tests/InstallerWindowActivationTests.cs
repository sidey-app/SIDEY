using Sidey.Installer;

namespace Sidey.Platform.Windows.Tests;

public sealed class InstallerWindowActivationTests
{
    [Fact]
    public void MissingWindowIsRetriedWithinTheBoundedSearch()
    {
        var api = new FakeActivationApi();

        bool activated = InstallerWindowActivation.TryActivateExisting(api, 3, 25);

        Assert.False(activated);
        Assert.Equal(3, api.FindCalls);
        Assert.Equal([25, 25], api.Delays);
        Assert.Empty(api.ShownWindows);
    }

    [Fact]
    public void MinimizedOwnerAndItsLastPopupAreRestoredBeforeActivation()
    {
        IntPtr owner = new(11);
        IntPtr popup = new(12);
        var api = new FakeActivationApi
        {
            FoundWindow = owner,
            LastActivePopup = popup,
            ForegroundAccepted = true,
        };
        api.MinimizedWindows.Add(owner);
        api.MinimizedWindows.Add(popup);

        bool activated = InstallerWindowActivation.TryActivateExisting(api, 1, 0);

        Assert.True(activated);
        Assert.Equal(
            [(owner, InstallerWindowActivation.Restore), (popup, InstallerWindowActivation.Restore)],
            api.ShownWindows);
        Assert.Equal(popup, api.ForegroundWindow);
        Assert.Equal(IntPtr.Zero, api.FlashedWindow);
    }

    [Fact]
    public void ForegroundDenialFlashesTheExistingWindowWithoutMakingItTopmost()
    {
        IntPtr owner = new(21);
        var api = new FakeActivationApi
        {
            FoundWindow = owner,
            LastActivePopup = owner,
            ForegroundAccepted = false,
        };

        bool activated = InstallerWindowActivation.TryActivateExisting(api, 1, 0);

        Assert.True(activated);
        Assert.Equal([(owner, InstallerWindowActivation.ShowNormal)], api.ShownWindows);
        Assert.Equal(owner, api.ForegroundWindow);
        Assert.Equal(owner, api.FlashedWindow);
    }

    [Fact]
    public void VanishedMarkedWindowIsIgnoredAndSearchContinues()
    {
        IntPtr stale = new(31);
        IntPtr current = new(32);
        var api = new FakeActivationApi
        {
            FoundWindows = new Queue<IntPtr>([stale, current]),
            ForegroundAccepted = true,
        };
        api.InvalidWindows.Add(stale);

        bool activated = InstallerWindowActivation.TryActivateExisting(api, 2, 10);

        Assert.True(activated);
        Assert.Equal([10], api.Delays);
        Assert.Equal(current, api.ForegroundWindow);
    }

    private sealed class FakeActivationApi : IInstallerWindowActivationApi
    {
        internal IntPtr FoundWindow { get; init; }

        internal Queue<IntPtr>? FoundWindows { get; init; }

        internal IntPtr LastActivePopup { get; init; }

        internal bool ForegroundAccepted { get; init; }

        internal HashSet<IntPtr> MinimizedWindows { get; } = [];

        internal HashSet<IntPtr> InvalidWindows { get; } = [];

        internal List<(IntPtr Window, int Command)> ShownWindows { get; } = [];

        internal List<int> Delays { get; } = [];

        internal int FindCalls { get; private set; }

        internal IntPtr ForegroundWindow { get; private set; }

        internal IntPtr FlashedWindow { get; private set; }

        public IntPtr FindMarkedWindow()
        {
            FindCalls++;
            return FoundWindows is { Count: > 0 } ? FoundWindows.Dequeue() : FoundWindow;
        }

        public IntPtr GetLastActivePopup(IntPtr window) =>
            LastActivePopup == IntPtr.Zero ? window : LastActivePopup;

        public bool IsWindow(IntPtr window) => !InvalidWindows.Contains(window);

        public bool IsMinimized(IntPtr window) => MinimizedWindows.Contains(window);

        public void ShowWindow(IntPtr window, int command) => ShownWindows.Add((window, command));

        public bool SetForegroundWindow(IntPtr window)
        {
            ForegroundWindow = window;
            return ForegroundAccepted;
        }

        public void FlashWindow(IntPtr window) => FlashedWindow = window;

        public void Delay(int milliseconds) => Delays.Add(milliseconds);
    }
}
