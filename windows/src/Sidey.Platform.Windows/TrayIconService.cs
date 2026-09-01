using System.Collections.Concurrent;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Sidey.Platform.Windows;

public enum TrayCommand
{
    ToggleOverlay = 1001,
    Compose = 1002,
    ToggleQuietMode = 1003,
    History = 1004,
    Groups = 1005,
    ToggleStartAtLogin = 1006,
    CheckUpdates = 1007,
    Settings = 1008,
    Exit = 1099,
}

public sealed record TrayMenuState(
    bool OverlayVisible,
    bool QuietMode,
    bool StartAtLogin,
    int UnreadCount,
    IReadOnlyList<TrayRoomMenuItem> Rooms,
    Guid? ActiveRoomId);

public sealed record TrayRoomMenuItem(Guid Id, string Name, int UnreadCount);

public sealed class TrayIconService : IDisposable
{
    private const string WindowClassName = "SIDEY.TrayIconWindow";
    private const uint TrayMessage = 0x8000 + 51;
    private const uint RefreshMessage = 0x8000 + 52;
    private const uint IconId = 1;
    private static readonly object RegistrationGate = new();
    private static readonly ConcurrentDictionary<nint, TrayIconService> Instances = new();
    private static readonly NativeMethods.WindowProcedure WindowProcedure = WndProc;
    private static bool _registered;

    private readonly ManualResetEventSlim _started = new(false);
    private readonly Thread _thread;
    private nint _window;
    private Exception? _startupError;
    private TrayMenuState _state = new(true, false, false, 0, [], null);
    private bool _disposed;

    private TrayIconService()
    {
        _thread = new Thread(Run)
        {
            IsBackground = true,
            Name = "SIDEY Tray",
        };
        _thread.SetApartmentState(ApartmentState.STA);
    }

    public event Action<TrayCommand>? CommandInvoked;
    public event Action<Guid>? RoomSelected;

    public static TrayIconService Start()
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The SIDEY tray requires Windows.");
        }

        var service = new TrayIconService();
        service._thread.Start();
        if (!service._started.Wait(TimeSpan.FromSeconds(10)))
        {
            throw new TimeoutException("SIDEY tray did not start within ten seconds.");
        }
        if (service._startupError is not null)
        {
            throw new InvalidOperationException("SIDEY tray failed to start.", service._startupError);
        }
        return service;
    }

    public void SetState(TrayMenuState state)
    {
        _state = state;
        if (_window != nint.Zero)
        {
            NativeMethods.PostMessage(_window, RefreshMessage, nint.Zero, nint.Zero);
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        if (_window != nint.Zero)
        {
            NativeMethods.PostMessage(_window, 0x0010, nint.Zero, nint.Zero);
        }
        if (_thread.IsAlive && !_thread.Join(TimeSpan.FromSeconds(5)))
        {
            throw new TimeoutException("SIDEY tray did not stop within five seconds.");
        }
        _started.Dispose();
    }

    private void Run()
    {
        try
        {
            EnsureClass();
            _window = NativeMethods.CreateWindowEx(
                0,
                WindowClassName,
                "SIDEY Tray",
                0,
                0,
                0,
                0,
                0,
                nint.Zero,
                nint.Zero,
                NativeMethods.GetModuleHandle(null),
                nint.Zero);
            if (_window == nint.Zero)
            {
                throw new Win32Exception(Marshal.GetLastPInvokeError(), "Tray window creation failed.");
            }
            Instances[_window] = this;
            AddIcon();
            _started.Set();
            while (NativeMethods.GetMessage(out var message, nint.Zero, 0, 0) > 0)
            {
                NativeMethods.TranslateMessage(ref message);
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
                RemoveIcon();
                Instances.TryRemove(_window, out _);
                _window = nint.Zero;
            }
        }
    }

    private void AddIcon()
    {
        var data = CreateIconData();
        if (!NativeMethods.ShellNotifyIcon(0, ref data))
        {
            throw new Win32Exception(Marshal.GetLastPInvokeError(), "Adding the SIDEY tray icon failed.");
        }
        data.TimeoutOrVersion = 4;
        NativeMethods.ShellNotifyIcon(4, ref data);
    }

    private void RemoveIcon()
    {
        var data = CreateIconData();
        NativeMethods.ShellNotifyIcon(2, ref data);
    }

    private NotifyIconData CreateIconData() => new()
    {
        Size = Marshal.SizeOf<NotifyIconData>(),
        Window = _window,
        Id = IconId,
        Flags = 0x1 | 0x2 | 0x4,
        CallbackMessage = TrayMessage,
        Icon = NativeMethods.LoadIcon(nint.Zero, new nint(32512)),
        Tip = _state.UnreadCount > 0 ? $"SIDEY · 읽지 않음 {_state.UnreadCount}" : "SIDEY",
        Info = string.Empty,
        InfoTitle = string.Empty,
    };

    private void ShowMenu()
    {
        var menu = NativeMethods.CreatePopupMenu();
        if (menu == nint.Zero)
        {
            return;
        }
        try
        {
            var roomCommands = new Dictionary<uint, Guid>();
            Append(menu, TrayCommand.ToggleOverlay, _state.OverlayVisible ? "오버레이 숨기기" : "오버레이 표시");
            Append(menu, TrayCommand.Compose, "메시지 작성");
            if (_state.Rooms.Count > 0)
            {
                NativeMethods.AppendMenu(menu, 0x800, 0, null);
                for (var index = 0; index < _state.Rooms.Count; index++)
                {
                    var room = _state.Rooms[index];
                    var command = (uint)(2000 + index);
                    roomCommands[command] = room.Id;
                    var label = room.UnreadCount > 0
                        ? $"{room.Name} ({room.UnreadCount})"
                        : room.Name;
                    NativeMethods.AppendMenu(
                        menu,
                        room.Id == _state.ActiveRoomId ? 0x0008u : 0u,
                        command,
                        label);
                }
            }
            Append(menu, TrayCommand.ToggleQuietMode, "조용히 모드", _state.QuietMode);
            NativeMethods.AppendMenu(menu, 0x800, 0, null);
            Append(menu, TrayCommand.History, "최근 기록");
            Append(menu, TrayCommand.Groups, "그룹 설정");
            Append(menu, TrayCommand.ToggleStartAtLogin, "로그인 시 실행", _state.StartAtLogin);
            Append(menu, TrayCommand.CheckUpdates, "업데이트 확인");
            Append(menu, TrayCommand.Settings, "설정");
            NativeMethods.AppendMenu(menu, 0x800, 0, null);
            Append(menu, TrayCommand.Exit, "종료");

            NativeMethods.GetCursorPos(out var point);
            NativeMethods.SetForegroundWindow(_window);
            var selected = NativeMethods.TrackPopupMenu(
                menu,
                0x0100 | 0x0002,
                point.X,
                point.Y,
                0,
                _window,
                nint.Zero);
            if (roomCommands.TryGetValue(selected, out var roomId))
            {
                RoomSelected?.Invoke(roomId);
            }
            else if (Enum.IsDefined(typeof(TrayCommand), (int)selected))
            {
                CommandInvoked?.Invoke((TrayCommand)selected);
            }
        }
        finally
        {
            NativeMethods.DestroyMenu(menu);
        }
    }

    private static void Append(nint menu, TrayCommand command, string label, bool isChecked = false)
    {
        var flags = isChecked ? 0x0008u : 0u;
        NativeMethods.AppendMenu(menu, flags, (nuint)command, label);
    }

    private static nint WndProc(nint window, uint message, nint wParam, nint lParam)
    {
        _ = wParam;
        if (Instances.TryGetValue(window, out var service))
        {
            if (message == TrayMessage)
            {
                var mouseMessage = unchecked((uint)(long)lParam) & 0xffff;
                if (mouseMessage is 0x0205 or 0x007B)
                {
                    service.ShowMenu();
                    return nint.Zero;
                }
                if (mouseMessage is 0x0202 or 0x0203)
                {
                    service.CommandInvoked?.Invoke(TrayCommand.Settings);
                    return nint.Zero;
                }
            }
            if (message == RefreshMessage)
            {
                var data = service.CreateIconData();
                NativeMethods.ShellNotifyIcon(1, ref data);
                return nint.Zero;
            }
            if (message == 0x0010)
            {
                service.RemoveIcon();
                NativeMethods.DestroyWindow(window);
                return nint.Zero;
            }
            if (message == 0x0002)
            {
                Instances.TryRemove(window, out _);
                NativeMethods.PostQuitMessage(0);
                return nint.Zero;
            }
        }
        return NativeMethods.DefWindowProc(window, message, wParam, lParam);
    }

    private static void EnsureClass()
    {
        lock (RegistrationGate)
        {
            if (_registered)
            {
                return;
            }
            var windowClass = new WindowClass
            {
                Size = Marshal.SizeOf<WindowClass>(),
                WindowProcedure = Marshal.GetFunctionPointerForDelegate(WindowProcedure),
                Instance = NativeMethods.GetModuleHandle(null),
                ClassName = WindowClassName,
            };
            if (NativeMethods.RegisterClassEx(ref windowClass) == 0)
            {
                throw new Win32Exception(Marshal.GetLastPInvokeError(), "Tray window class registration failed.");
            }
            _registered = true;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint { public int X; public int Y; }

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

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyIconData
    {
        public int Size;
        public nint Window;
        public uint Id;
        public uint Flags;
        public uint CallbackMessage;
        public nint Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Tip;
        public uint State;
        public uint StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Info;
        public uint TimeoutOrVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string InfoTitle;
        public uint InfoFlags;
        public Guid Item;
        public nint BalloonIcon;
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
        [DllImport("user32.dll")] public static extern nint DefWindowProc(nint window, uint message, nint wParam, nint lParam);
        [DllImport("user32.dll")] public static extern int GetMessage(out NativeMessage message, nint window, uint minimum, uint maximum);
        [DllImport("user32.dll")] public static extern bool TranslateMessage(ref NativeMessage message);
        [DllImport("user32.dll")] public static extern nint DispatchMessage(ref NativeMessage message);
        [DllImport("user32.dll")] public static extern bool PostMessage(nint window, uint message, nint wParam, nint lParam);
        [DllImport("user32.dll")] public static extern void PostQuitMessage(int exitCode);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern nint GetModuleHandle(string? moduleName);
        [DllImport("shell32.dll", EntryPoint = "Shell_NotifyIconW", CharSet = CharSet.Unicode, SetLastError = true)] public static extern bool ShellNotifyIcon(uint message, ref NotifyIconData data);
        [DllImport("user32.dll")] public static extern nint LoadIcon(nint instance, nint iconName);
        [DllImport("user32.dll")] public static extern nint CreatePopupMenu();
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool AppendMenu(nint menu, uint flags, nuint item, string? label);
        [DllImport("user32.dll")] public static extern uint TrackPopupMenu(nint menu, uint flags, int x, int y, int reserved, nint window, nint rectangle);
        [DllImport("user32.dll")] public static extern bool DestroyMenu(nint menu);
        [DllImport("user32.dll")] public static extern bool GetCursorPos(out NativePoint point);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(nint window);
    }
}
