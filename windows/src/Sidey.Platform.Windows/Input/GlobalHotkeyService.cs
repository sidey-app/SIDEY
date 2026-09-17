using System.Collections.Concurrent;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;

namespace Sidey.Platform.Windows.Input;

/// <summary>
/// Registers only the combinations chosen in settings with RegisterHotKey. Windows
/// reports when one of those combinations is pressed; other keyboard input never
/// reaches this service.
/// </summary>
public sealed class GlobalHotkeyService : IGlobalShortcutRegistrar, IDisposable
{
    private const string WindowClassName = "SIDEY.GlobalHotkeyWindow";
    private const uint DestroyMessage = 0x0002;
    private const uint CloseMessage = 0x0010;
    private const uint HotkeyMessage = 0x0312;
    private const uint InvokeMessage = 0x8000 + 61;
    private const uint AltModifier = 0x0001;
    private const uint ControlModifier = 0x0002;
    private const uint ShiftModifier = 0x0004;
    private const uint WindowsModifier = 0x0008;
    private const uint NoRepeatModifier = 0x4000;
    private const int HotkeyAlreadyRegisteredError = 1409;
    private static readonly nint s_messageOnlyParent = -3;
    private static readonly Lock s_registrationGate = new();
    private static readonly ConcurrentDictionary<nint, GlobalHotkeyService> s_instances = new();
    private static readonly NativeMethods.WindowProcedure s_windowProcedure = WndProc;
    private static bool s_registered;

    private readonly ManualResetEventSlim _started = new(false);
    private readonly Thread _thread;
    private readonly Action<string, Exception>? _diagnostic;
    private readonly ConcurrentQueue<Action> _invocations = new();
    private readonly Dictionary<GlobalShortcutAction, Registration> _registrations = [];
    private nint _window;
    private Exception? _startupError;
    private volatile bool _disposed;

    private GlobalHotkeyService(Action<string, Exception>? diagnostic)
    {
        _diagnostic = diagnostic;
        _thread = new Thread(Run)
        {
            IsBackground = true,
            Name = "SIDEY Global Shortcuts",
        };
        _thread.SetApartmentState(ApartmentState.STA);
    }

    /// <summary>Raised on the shortcut thread. Handlers should hand work off and return.</summary>
    public event Action<GlobalShortcutAction>? Pressed;

    internal nint WindowHandle => _window;

    public static GlobalHotkeyService Start(Action<string, Exception>? diagnostic = null)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("SIDEY global shortcuts require Windows.");
        }

        var service = new GlobalHotkeyService(diagnostic);
        service._thread.Start();
        if (!service._started.Wait(TimeSpan.FromSeconds(10)))
        {
            throw new TimeoutException("SIDEY global shortcuts did not start within ten seconds.");
        }
        if (service._startupError is not null)
        {
            throw new InvalidOperationException("SIDEY global shortcuts failed to start.", service._startupError);
        }
        return service;
    }

    public GlobalShortcutRegistrationStatus Register(GlobalShortcutAction action, GlobalShortcut? shortcut)
    {
        if (!Enum.IsDefined(action))
        {
            throw new ArgumentOutOfRangeException(nameof(action));
        }
        if (shortcut is { } requested && requested.Validate() != GlobalShortcutValidation.Valid)
        {
            throw new ArgumentException("Only a valid global shortcut can be registered.", nameof(shortcut));
        }

        GlobalShortcutRegistrationStatus status = shortcut is null
            ? GlobalShortcutRegistrationStatus.NotSet
            : GlobalShortcutRegistrationStatus.Unavailable;
        InvokeOnWindowThread(() => status = RegisterOnWindowThread(action, shortcut));
        return status;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        nint window = _window;
        if (window != nint.Zero)
        {
            NativeMethods.PostMessage(window, CloseMessage, nint.Zero, nint.Zero);
        }
        if (_thread.IsAlive && !_thread.Join(TimeSpan.FromSeconds(5)))
        {
            throw new TimeoutException("SIDEY global shortcuts did not stop within five seconds.");
        }
        _started.Dispose();
    }

    // Each action alternates between two ids so a replacement can be registered
    // before the previous combination is released.
    internal static (int Primary, int Alternate) HotkeyIds(GlobalShortcutAction action) =>
        ((int)action * 2 + 1, (int)action * 2 + 2);

    internal static uint NativeModifiers(GlobalShortcutModifiers modifiers)
    {
        uint native = NoRepeatModifier;
        if (modifiers.HasFlag(GlobalShortcutModifiers.Alt))
        {
            native |= AltModifier;
        }
        if (modifiers.HasFlag(GlobalShortcutModifiers.Control))
        {
            native |= ControlModifier;
        }
        if (modifiers.HasFlag(GlobalShortcutModifiers.Shift))
        {
            native |= ShiftModifier;
        }
        if (modifiers.HasFlag(GlobalShortcutModifiers.Windows))
        {
            native |= WindowsModifier;
        }
        return native;
    }

    private void InvokeOnWindowThread(Action invocation)
    {
        nint window = _window;
        if (_disposed || window == nint.Zero)
        {
            return;
        }
        if (Environment.CurrentManagedThreadId == _thread.ManagedThreadId)
        {
            invocation();
            return;
        }

        // RegisterHotKey belongs to the window thread. SendMessage returns after
        // that thread has drained the queued work.
        _invocations.Enqueue(invocation);
        NativeMethods.SendMessage(window, InvokeMessage, nint.Zero, nint.Zero);
    }

    private GlobalShortcutRegistrationStatus RegisterOnWindowThread(
        GlobalShortcutAction action,
        GlobalShortcut? shortcut)
    {
        bool hasCurrent = _registrations.TryGetValue(action, out Registration current);
        if (shortcut is not { } requested)
        {
            if (hasCurrent)
            {
                NativeMethods.UnregisterHotKey(_window, current.Id);
                _registrations.Remove(action);
            }
            return GlobalShortcutRegistrationStatus.NotSet;
        }

        if (hasCurrent && current.Shortcut == requested)
        {
            return GlobalShortcutRegistrationStatus.Registered;
        }

        (int Primary, int Alternate) ids = HotkeyIds(action);
        int id = hasCurrent && current.Id == ids.Primary ? ids.Alternate : ids.Primary;
        if (!NativeMethods.RegisterHotKey(_window, id, NativeModifiers(requested.Modifiers), (uint)requested.KeyCode))
        {
            int error = Marshal.GetLastPInvokeError();
            _diagnostic?.Invoke($"global-shortcut-register action={action}", new Win32Exception(error));
            return error == HotkeyAlreadyRegisteredError
                ? GlobalShortcutRegistrationStatus.InUse
                : GlobalShortcutRegistrationStatus.Unavailable;
        }

        if (hasCurrent)
        {
            NativeMethods.UnregisterHotKey(_window, current.Id);
        }
        _registrations[action] = new Registration(id, requested);
        return GlobalShortcutRegistrationStatus.Registered;
    }

    private void RaisePressed(int id)
    {
        foreach (KeyValuePair<GlobalShortcutAction, Registration> registration in _registrations)
        {
            if (registration.Value.Id != id)
            {
                continue;
            }

            try
            {
                Pressed?.Invoke(registration.Key);
            }
            catch (Exception exception)
            {
                _diagnostic?.Invoke("global-shortcut-pressed", exception);
            }
            return;
        }
    }

    private void DrainInvocations()
    {
        while (_invocations.TryDequeue(out Action? invocation))
        {
            try
            {
                invocation();
            }
            catch (Exception exception)
            {
                _diagnostic?.Invoke("global-shortcut-invoke", exception);
            }
        }
    }

    private void UnregisterAll()
    {
        foreach (Registration registration in _registrations.Values)
        {
            NativeMethods.UnregisterHotKey(_window, registration.Id);
        }
        _registrations.Clear();
    }

    private void Run()
    {
        try
        {
            EnsureClass();
            _window = NativeMethods.CreateWindowEx(
                0,
                WindowClassName,
                "SIDEY Global Shortcuts",
                0,
                0,
                0,
                0,
                0,
                s_messageOnlyParent,
                nint.Zero,
                NativeMethods.GetModuleHandle(null),
                nint.Zero);
            if (_window == nint.Zero)
            {
                throw new Win32Exception(Marshal.GetLastPInvokeError(), "Global shortcut window creation failed.");
            }
            s_instances[_window] = this;
            _started.Set();
            while (NativeMethods.GetMessage(out NativeMessage message, nint.Zero, 0, 0) > 0)
            {
                NativeMethods.DispatchMessage(ref message);
            }
        }
        catch (Exception exception)
        {
            _startupError = exception;
            _started.Set();
        }
        finally
        {
            if (_window != nint.Zero)
            {
                UnregisterAll();
                s_instances.TryRemove(_window, out _);
                _window = nint.Zero;
            }
        }
    }

    private static nint WndProc(nint window, uint message, nint wParam, nint lParam)
    {
        if (s_instances.TryGetValue(window, out GlobalHotkeyService? service))
        {
            if (message == HotkeyMessage)
            {
                service.RaisePressed(unchecked((int)(long)wParam));
                return nint.Zero;
            }
            if (message == InvokeMessage)
            {
                service.DrainInvocations();
                return nint.Zero;
            }
            if (message == CloseMessage)
            {
                service.UnregisterAll();
                NativeMethods.DestroyWindow(window);
                return nint.Zero;
            }
            if (message == DestroyMessage)
            {
                s_instances.TryRemove(window, out _);
                NativeMethods.PostQuitMessage(0);
                return nint.Zero;
            }
        }
        return NativeMethods.DefWindowProc(window, message, wParam, lParam);
    }

    private static void EnsureClass()
    {
        lock (s_registrationGate)
        {
            if (s_registered)
            {
                return;
            }
            var windowClass = new WindowClass
            {
                Size = Marshal.SizeOf<WindowClass>(),
                WindowProcedure = Marshal.GetFunctionPointerForDelegate(s_windowProcedure),
                Instance = NativeMethods.GetModuleHandle(null),
                ClassName = WindowClassName,
            };
            if (NativeMethods.RegisterClassEx(ref windowClass) == 0)
            {
                throw new Win32Exception(Marshal.GetLastPInvokeError(), "Global shortcut window class registration failed.");
            }
            s_registered = true;
        }
    }

    private readonly record struct Registration(int Id, GlobalShortcut Shortcut);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeMessage
    {
        public nint Window;
        public uint Message;
        public nuint WParam;
        public nint LParam;
        public uint Time;
        public NativePoint Point;
        public uint Private;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WindowClass
    {
        public int Size;
        public uint Style;
        public nint WindowProcedure;
        public int ClassExtra;
        public int WindowExtra;
        public nint Instance;
        public nint Icon;
        public nint Cursor;
        public nint Background;
        public string? MenuName;
        public string ClassName;
        public nint SmallIcon;
    }

    private static class NativeMethods
    {
        [UnmanagedFunctionPointer(CallingConvention.Winapi)]
        public delegate nint WindowProcedure(nint window, uint message, nint wParam, nint lParam);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern ushort RegisterClassEx(ref WindowClass windowClass);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern nint CreateWindowEx(uint exStyle, string className, string windowName, uint style, int x, int y, int width, int height, nint parent, nint menu, nint instance, nint parameter);
        [DllImport("user32.dll")] public static extern bool DestroyWindow(nint window);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern nint DefWindowProc(nint window, uint message, nint wParam, nint lParam);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetMessage(out NativeMessage message, nint window, uint minimum, uint maximum);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern nint DispatchMessage(ref NativeMessage message);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool PostMessage(nint window, uint message, nint wParam, nint lParam);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern nint SendMessage(nint window, uint message, nint wParam, nint lParam);
        [DllImport("user32.dll")] public static extern void PostQuitMessage(int exitCode);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern nint GetModuleHandle(string? moduleName);
        [DllImport("user32.dll", SetLastError = true)][return: MarshalAs(UnmanagedType.Bool)] public static extern bool RegisterHotKey(nint window, int id, uint modifiers, uint virtualKey);
        [DllImport("user32.dll", SetLastError = true)][return: MarshalAs(UnmanagedType.Bool)] public static extern bool UnregisterHotKey(nint window, int id);
    }
}
