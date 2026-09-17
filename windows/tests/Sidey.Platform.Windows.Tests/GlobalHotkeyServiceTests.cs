using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using Sidey.Core.Domain;

namespace Sidey.Platform.Windows.Tests;

public sealed class GlobalHotkeyServiceTests
{
    private const uint HotkeyMessage = 0x0312;

    // Rarely used combinations. Another app may still own one, so each test takes
    // the first combination Windows accepts.
    private static readonly GlobalShortcut[] s_candidates =
    [
        new(GlobalShortcutModifiers.Control | GlobalShortcutModifiers.Shift, 0x7A),
        new(GlobalShortcutModifiers.Alt | GlobalShortcutModifiers.Shift, 0x7A),
        new(GlobalShortcutModifiers.Control | GlobalShortcutModifiers.Shift, 0x79),
        new(GlobalShortcutModifiers.Alt | GlobalShortcutModifiers.Shift, 0x79),
        new(GlobalShortcutModifiers.Control | GlobalShortcutModifiers.Shift, 0x78),
        new(GlobalShortcutModifiers.Alt | GlobalShortcutModifiers.Shift, 0x78),
    ];

    [Fact]
    public void NativeModifiersAlwaysSuppressAutoRepeat()
    {
        Assert.Equal(
            0x4006u,
            GlobalHotkeyService.NativeModifiers(GlobalShortcutModifiers.Control | GlobalShortcutModifiers.Shift));
        Assert.Equal(
            0x4005u,
            GlobalHotkeyService.NativeModifiers(GlobalShortcutModifiers.Alt | GlobalShortcutModifiers.Shift));
    }

    [Fact]
    public void EachActionOwnsDistinctApplicationHotkeyIds()
    {
        int[] ids = [.. GlobalShortcutPreferences.Actions.SelectMany(action =>
        {
            (int Primary, int Alternate) pair = GlobalHotkeyService.HotkeyIds(action);
            return new[] { pair.Primary, pair.Alternate };
        })];

        Assert.Equal(ids.Length, ids.Distinct().Count());
        Assert.All(ids, id => Assert.InRange(id, 1, 0xBFFF));
    }

    [Fact]
    public void InvalidRequestsAreRejectedBeforeWindowsIsCalled()
    {
        using var service = GlobalHotkeyService.Start();

        Assert.Throws<ArgumentException>(() => service.Register(
            GlobalShortcutAction.Compose,
            new GlobalShortcut(GlobalShortcutModifiers.Control | GlobalShortcutModifiers.Alt, 0x4D)));
        Assert.Throws<ArgumentOutOfRangeException>(() => service.Register((GlobalShortcutAction)99, null));
    }

    [Fact]
    public void ConflictsKeepThePreviousCombinationAndClearingReleasesIt()
    {
        using var first = GlobalHotkeyService.Start();
        using var second = GlobalHotkeyService.Start();
        if (RegisterFirstAvailable(first, GlobalShortcutAction.Compose, exclude: null) is not { } owned)
        {
            // Without an interactive desktop Windows accepts no hotkey, so there is nothing to observe.
            return;
        }

        Assert.Equal(GlobalShortcutRegistrationStatus.InUse, second.Register(GlobalShortcutAction.Compose, owned));
        Assert.Equal(GlobalShortcutRegistrationStatus.Registered, first.Register(GlobalShortcutAction.Compose, owned));
        if (RegisterFirstAvailable(second, GlobalShortcutAction.ToggleOverlay, exclude: owned) is not { } other)
        {
            return;
        }

        Assert.Equal(GlobalShortcutRegistrationStatus.InUse, first.Register(GlobalShortcutAction.Compose, other));
        Assert.Equal(GlobalShortcutRegistrationStatus.InUse, second.Register(GlobalShortcutAction.ToggleQuietMode, owned));

        Assert.Equal(GlobalShortcutRegistrationStatus.NotSet, first.Register(GlobalShortcutAction.Compose, null));
        Assert.Equal(GlobalShortcutRegistrationStatus.Registered, second.Register(GlobalShortcutAction.ToggleQuietMode, owned));
    }

    [Fact]
    public async Task PressedIsRaisedOnlyForTheCurrentRegistration()
    {
        using var service = GlobalHotkeyService.Start();
        if (RegisterFirstAvailable(service, GlobalShortcutAction.ToggleQuietMode, exclude: null) is null)
        {
            return;
        }

        var pressed = new ConcurrentQueue<GlobalShortcutAction>();
        var received = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        service.Pressed += action =>
        {
            pressed.Enqueue(action);
            received.TrySetResult();
        };
        (int Primary, int Alternate) ids = GlobalHotkeyService.HotkeyIds(GlobalShortcutAction.ToggleQuietMode);

        // Messages for one window arrive in order, so the stale id is handled first.
        Assert.True(PostMessage(service.WindowHandle, HotkeyMessage, ids.Alternate, nint.Zero));
        Assert.True(PostMessage(service.WindowHandle, HotkeyMessage, ids.Primary, nint.Zero));
        await received.Task.WaitAsync(TimeSpan.FromSeconds(5));

        Assert.Equal([GlobalShortcutAction.ToggleQuietMode], pressed);
    }

    [Fact]
    public void RegistrationAfterDisposeReportsTheShortcutAsUnavailable()
    {
        var service = GlobalHotkeyService.Start();
        service.Dispose();

        Assert.Equal(
            GlobalShortcutRegistrationStatus.Unavailable,
            service.Register(GlobalShortcutAction.Compose, s_candidates[0]));
        Assert.Equal(GlobalShortcutRegistrationStatus.NotSet, service.Register(GlobalShortcutAction.Compose, null));
    }

    private static GlobalShortcut? RegisterFirstAvailable(
        GlobalHotkeyService service,
        GlobalShortcutAction action,
        GlobalShortcut? exclude)
    {
        foreach (GlobalShortcut candidate in s_candidates)
        {
            if (candidate != exclude
                && service.Register(action, candidate) == GlobalShortcutRegistrationStatus.Registered)
            {
                return candidate;
            }
        }
        return null;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostMessage(nint window, uint message, nint wParam, nint lParam);
}
