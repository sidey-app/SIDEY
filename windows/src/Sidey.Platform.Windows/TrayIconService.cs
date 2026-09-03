using System.Collections.Concurrent;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Sidey.Core.Localization;

namespace Sidey.Platform.Windows;

public enum TrayCommand
{
    Open = 1000,
    ToggleOverlay = 1001,
    Compose = 1002,
    ToggleQuietMode = 1003,
    History = 1004,
    Groups = 1005,
    ToggleStartAtLogin = 1006,
    CheckUpdates = 1007,
    Settings = 1008,
    Store = 1009,
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
    private const uint NotificationMessage = 0x8000 + 53;
    private const uint IconId = 1;
    private const uint NotifyIconMessage = 0x1;
    private const uint NotifyIconIcon = 0x2;
    private const uint NotifyIconTip = 0x4;
    private const uint NotifyIconInfo = 0x10;
    private const uint NotifyIconShowTip = 0x80;
    private const uint NotifyInfoWarning = 0x2;
    private static readonly object RegistrationGate = new();
    private static readonly ConcurrentDictionary<nint, TrayIconService> Instances = new();
    private static readonly NativeMethods.WindowProcedure WindowProcedure = WndProc;
    private static bool _registered;

    private readonly ManualResetEventSlim _started = new(false);
    private readonly Thread _thread;
    private nint _window;
    private nint _icon;
    private nint _baseIcon;
    private nint _unreadIcon;
    private bool _ownsBaseIcon;
    private bool _ownsUnreadIcon;
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

    public void NotifyConnectionFailure()
    {
        if (_window != nint.Zero)
        {
            NativeMethods.PostMessage(_window, NotificationMessage, nint.Zero, nint.Zero);
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
            _baseIcon = LoadSideyIcon();
            _unreadIcon = CreateUnreadIcon(_baseIcon);
            _ownsUnreadIcon = _unreadIcon != nint.Zero;
            _icon = _baseIcon;
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
            if (_ownsUnreadIcon && _unreadIcon != nint.Zero)
            {
                NativeMethods.DestroyIcon(_unreadIcon);
                _unreadIcon = nint.Zero;
                _ownsUnreadIcon = false;
            }
            if (_ownsBaseIcon && _baseIcon != nint.Zero)
            {
                NativeMethods.DestroyIcon(_baseIcon);
                _baseIcon = nint.Zero;
                _ownsBaseIcon = false;
            }
            _icon = nint.Zero;
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
        Flags = NotifyIconMessage | NotifyIconIcon | NotifyIconTip | NotifyIconShowTip,
        CallbackMessage = TrayMessage,
        Icon = _icon,
        Tip = _state.UnreadCount > 0
            ? I18n.Format("tray.unreadTooltip", _state.UnreadCount)
            : "SIDEY",
        Info = string.Empty,
        InfoTitle = string.Empty,
    };

    private nint LoadSideyIcon()
    {
        var path = Path.Combine(
            SideyDeploymentPaths.DeploymentRoot(),
            "Assets",
            "Icons",
            "SideyAppIcon.ico");
        var icon = File.Exists(path)
            ? NativeMethods.LoadImage(
                nint.Zero,
                path,
                1,
                0,
                0,
                0x10 | 0x40)
            : nint.Zero;
        if (icon != nint.Zero)
        {
            _ownsBaseIcon = true;
            return icon;
        }

        return NativeMethods.LoadIcon(nint.Zero, new nint(32512));
    }

    internal static nint CreateUnreadIcon(nint sourceIcon)
    {
        if (sourceIcon == nint.Zero
            || !NativeMethods.GetIconInfo(sourceIcon, out var iconInformation)
            || iconInformation.ColorBitmap == nint.Zero)
        {
            return nint.Zero;
        }

        nint colorDc = nint.Zero;
        nint maskDc = nint.Zero;
        nint maskBrush = nint.Zero;
        try
        {
            if (NativeMethods.GetObject(
                    iconInformation.ColorBitmap,
                    Marshal.SizeOf<NativeBitmap>(),
                    out var bitmap) == 0
                || bitmap.Width <= 0
                || bitmap.Height == 0)
            {
                return nint.Zero;
            }

            int width = bitmap.Width;
            int height = Math.Abs(bitmap.Height);
            var pixels = new byte[checked(width * height * 4)];
            var bitmapInfo = new BitmapInfo
            {
                Header = new BitmapInfoHeader
                {
                    Size = (uint)Marshal.SizeOf<BitmapInfoHeader>(),
                    Width = width,
                    Height = -height,
                    Planes = 1,
                    BitCount = 32,
                    Compression = 0,
                    SizeImage = (uint)pixels.Length,
                },
            };

            colorDc = NativeMethods.CreateCompatibleDC(nint.Zero);
            if (colorDc == nint.Zero
                || NativeMethods.GetDIBits(
                    colorDc,
                    iconInformation.ColorBitmap,
                    0,
                    (uint)height,
                    pixels,
                    ref bitmapInfo,
                    0) == 0)
            {
                return nint.Zero;
            }

            TrayUnreadBadgeRenderer.Apply(pixels, width, height);
            if (NativeMethods.SetDIBits(
                    colorDc,
                    iconInformation.ColorBitmap,
                    0,
                    (uint)height,
                    pixels,
                    ref bitmapInfo,
                    0) == 0)
            {
                return nint.Zero;
            }

            if (iconInformation.MaskBitmap != nint.Zero)
            {
                maskDc = NativeMethods.CreateCompatibleDC(nint.Zero);
                if (maskDc != nint.Zero)
                {
                    nint previousBitmap = NativeMethods.SelectObject(maskDc, iconInformation.MaskBitmap);
                    maskBrush = NativeMethods.CreateSolidBrush(0);
                    if (maskBrush != nint.Zero)
                    {
                        nint previousBrush = NativeMethods.SelectObject(maskDc, maskBrush);
                        nint previousPen = NativeMethods.SelectObject(
                            maskDc,
                            NativeMethods.GetStockObject(8));
                        GetBadgeBounds(width, height, out int left, out int top, out int right, out int bottom);
                        NativeMethods.Ellipse(maskDc, left, top, right, bottom);
                        NativeMethods.SelectObject(maskDc, previousPen);
                        NativeMethods.SelectObject(maskDc, previousBrush);
                    }
                    NativeMethods.SelectObject(maskDc, previousBitmap);
                }
            }

            iconInformation.IsIcon = true;
            return NativeMethods.CreateIconIndirect(ref iconInformation);
        }
        finally
        {
            if (maskBrush != nint.Zero)
            {
                NativeMethods.DeleteObject(maskBrush);
            }
            if (maskDc != nint.Zero)
            {
                NativeMethods.DeleteDC(maskDc);
            }
            if (colorDc != nint.Zero)
            {
                NativeMethods.DeleteDC(colorDc);
            }
            if (iconInformation.ColorBitmap != nint.Zero)
            {
                NativeMethods.DeleteObject(iconInformation.ColorBitmap);
            }
            if (iconInformation.MaskBitmap != nint.Zero)
            {
                NativeMethods.DeleteObject(iconInformation.MaskBitmap);
            }
        }
    }

    private static void GetBadgeBounds(
        int width,
        int height,
        out int left,
        out int top,
        out int right,
        out int bottom)
    {
        double scale = Math.Min(width, height);
        double radius = Math.Max(2.5d, scale * 0.19d);
        double margin = Math.Max(1d, scale * 0.04d);
        double centerX = width - margin - radius;
        double centerY = margin + radius;
        left = Math.Max(0, (int)Math.Floor(centerX - radius));
        top = Math.Max(0, (int)Math.Floor(centerY - radius));
        right = Math.Min(width, (int)Math.Ceiling(centerX + radius) + 1);
        bottom = Math.Min(height, (int)Math.Ceiling(centerY + radius) + 1);
    }

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
            Append(menu, TrayCommand.Open, I18n.Get("tray.open"));
            NativeMethods.SetMenuDefaultItem(menu, (uint)TrayCommand.Open, false);
            NativeMethods.AppendMenu(menu, 0x800, 0, null);
            Append(menu, TrayCommand.ToggleOverlay, _state.OverlayVisible
                ? I18n.Get("tray.hideOverlay")
                : I18n.Get("tray.showOverlay"));
            Append(menu, TrayCommand.Compose, I18n.Get("tray.compose"), isEnabled: _state.Rooms.Count > 0);
            NativeMethods.AppendMenu(menu, 0x800, 0, null);

            var roomsMenu = NativeMethods.CreatePopupMenu();
            if (roomsMenu != nint.Zero)
            {
                if (_state.Rooms.Count == 0)
                {
                    NativeMethods.AppendMenu(roomsMenu, 0x0001, 0, I18n.Get("tray.noGroups"));
                }
                else
                {
                    for (var index = 0; index < _state.Rooms.Count; index++)
                    {
                        var room = _state.Rooms[index];
                        var command = (uint)(2000 + index);
                        roomCommands[command] = room.Id;
                        var label = room.UnreadCount > 0
                            ? $"{room.Name} ({room.UnreadCount})"
                            : room.Name;
                        NativeMethods.AppendMenu(
                            roomsMenu,
                            room.Id == _state.ActiveRoomId ? 0x0008u : 0u,
                            command,
                            label);
                    }
                }
                var roomsFlags = 0x0010u | (_state.Rooms.Count == 0 ? 0x0001u : 0u);
                NativeMethods.AppendMenu(menu, roomsFlags, (nuint)roomsMenu, I18n.Get("tray.activeGroup"));
            }
            Append(menu, TrayCommand.ToggleQuietMode, I18n.Get("tray.quietMode"), _state.QuietMode);
            Append(menu, TrayCommand.History, I18n.Get("tray.history"), isEnabled: _state.Rooms.Count > 0);
            Append(menu, TrayCommand.Store, I18n.Get("tray.store"));
            Append(menu, TrayCommand.Groups, I18n.Get("tray.groups"));
            Append(menu, TrayCommand.ToggleStartAtLogin, I18n.Get("tray.startup"), _state.StartAtLogin);
            NativeMethods.AppendMenu(menu, 0x800, 0, null);
            Append(menu, TrayCommand.CheckUpdates, I18n.Get("tray.checkUpdates"));
            Append(menu, TrayCommand.Settings, I18n.Get("tray.settings"));
            NativeMethods.AppendMenu(menu, 0x800, 0, null);
            Append(menu, TrayCommand.Exit, I18n.Get("tray.exit"));

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

    private static void Append(
        nint menu,
        TrayCommand command,
        string label,
        bool isChecked = false,
        bool isEnabled = true)
    {
        var flags = (isChecked ? 0x0008u : 0u) | (isEnabled ? 0u : 0x0001u);
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
                if (mouseMessage is 0x0202 or 0x0203 or 0x0405)
                {
                    service.CommandInvoked?.Invoke(TrayCommand.Open);
                    return nint.Zero;
                }
            }
            if (message == RefreshMessage)
            {
                service._icon = service._state.UnreadCount > 0
                    && service._unreadIcon != nint.Zero
                    ? service._unreadIcon
                    : service._baseIcon;
                var data = service.CreateIconData();
                NativeMethods.ShellNotifyIcon(1, ref data);
                return nint.Zero;
            }
            if (message == NotificationMessage)
            {
                var data = service.CreateIconData();
                data.Flags |= NotifyIconInfo;
                data.InfoTitle = I18n.Get("tray.connectionFailedTitle");
                data.Info = I18n.Get("tray.connectionFailedBody");
                data.InfoFlags = NotifyInfoWarning;
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
    private struct IconInfo
    {
        [MarshalAs(UnmanagedType.Bool)] public bool IsIcon;
        public uint XHotspot;
        public uint YHotspot;
        public nint MaskBitmap;
        public nint ColorBitmap;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeBitmap
    {
        public int Type;
        public int Width;
        public int Height;
        public int WidthBytes;
        public ushort Planes;
        public ushort BitsPixel;
        public nint Bits;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfoHeader
    {
        public uint Size;
        public int Width;
        public int Height;
        public ushort Planes;
        public ushort BitCount;
        public uint Compression;
        public uint SizeImage;
        public int XPelsPerMeter;
        public int YPelsPerMeter;
        public uint ColorsUsed;
        public uint ColorsImportant;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfo
    {
        public BitmapInfoHeader Header;
        public uint Colors;
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
        [DllImport("user32.dll", EntryPoint = "LoadImageW", CharSet = CharSet.Unicode, SetLastError = true)] public static extern nint LoadImage(nint instance, string name, uint type, int width, int height, uint flags);
        [DllImport("user32.dll")][return: MarshalAs(UnmanagedType.Bool)] public static extern bool DestroyIcon(nint icon);
        [DllImport("user32.dll")][return: MarshalAs(UnmanagedType.Bool)] public static extern bool GetIconInfo(nint icon, out IconInfo iconInformation);
        [DllImport("user32.dll")] public static extern nint CreateIconIndirect(ref IconInfo iconInformation);
        [DllImport("user32.dll")] public static extern nint CreatePopupMenu();
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool AppendMenu(nint menu, uint flags, nuint item, string? label);
        [DllImport("user32.dll")] public static extern bool SetMenuDefaultItem(nint menu, uint item, [MarshalAs(UnmanagedType.Bool)] bool byPosition);
        [DllImport("user32.dll")] public static extern uint TrackPopupMenu(nint menu, uint flags, int x, int y, int reserved, nint window, nint rectangle);
        [DllImport("user32.dll")] public static extern bool DestroyMenu(nint menu);
        [DllImport("user32.dll")] public static extern bool GetCursorPos(out NativePoint point);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(nint window);
        [DllImport("gdi32.dll", EntryPoint = "GetObjectW")]
        public static extern int GetObject(nint value, int size, out NativeBitmap bitmap);
        [DllImport("gdi32.dll")] public static extern nint CreateCompatibleDC(nint deviceContext);
        [DllImport("gdi32.dll")][return: MarshalAs(UnmanagedType.Bool)] public static extern bool DeleteDC(nint deviceContext);
        [DllImport("gdi32.dll")][return: MarshalAs(UnmanagedType.Bool)] public static extern bool DeleteObject(nint value);
        [DllImport("gdi32.dll")] public static extern nint SelectObject(nint deviceContext, nint value);
        [DllImport("gdi32.dll")] public static extern nint CreateSolidBrush(uint color);
        [DllImport("gdi32.dll")] public static extern nint GetStockObject(int objectIndex);
        [DllImport("gdi32.dll")][return: MarshalAs(UnmanagedType.Bool)] public static extern bool Ellipse(nint deviceContext, int left, int top, int right, int bottom);
        [DllImport("gdi32.dll")]
        public static extern int GetDIBits(
            nint deviceContext,
            nint bitmap,
            uint start,
            uint lines,
            [Out] byte[] bits,
            ref BitmapInfo bitmapInfo,
            uint usage);
        [DllImport("gdi32.dll")]
        public static extern int SetDIBits(
            nint deviceContext,
            nint bitmap,
            uint start,
            uint lines,
            byte[] bits,
            ref BitmapInfo bitmapInfo,
            uint usage);
    }
}
