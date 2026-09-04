using System.Runtime.InteropServices;

namespace Sidey.Platform.Windows;

internal enum TrayMenuIcon
{
    Overlay,
    Compose,
    Rooms,
    Room,
    Empty,
    QuietMode,
    History,
    Store,
    Groups,
    StartAtLogin,
    CheckUpdates,
    Settings,
    Exit,
}

internal sealed class TrayMenuIconSet(int size) : IDisposable
{
    private const int MenuTextColor = 7;
    private readonly int _size = Math.Clamp(size, 16, 32);
    private readonly Dictionary<TrayMenuIcon, nint> _bitmaps = [];

    internal nint Get(TrayMenuIcon icon)
    {
        if (_bitmaps.TryGetValue(icon, out var bitmap))
        {
            return bitmap;
        }

        bitmap = CreateBitmap(Glyph(icon));
        if (bitmap != nint.Zero)
        {
            _bitmaps.Add(icon, bitmap);
        }
        return bitmap;
    }

    public void Dispose()
    {
        foreach (var bitmap in _bitmaps.Values)
        {
            NativeMethods.DeleteObject(bitmap);
        }
        _bitmaps.Clear();
    }

    internal static string Glyph(TrayMenuIcon icon) => icon switch
    {
        TrayMenuIcon.Overlay => "\uE890",
        TrayMenuIcon.Compose => "\uE70F",
        TrayMenuIcon.Rooms => "\uE716",
        TrayMenuIcon.Room => "\uE77B",
        TrayMenuIcon.Empty => "\uE711",
        TrayMenuIcon.QuietMode => "\uE708",
        TrayMenuIcon.History => "\uE81C",
        TrayMenuIcon.Store => "\uE719",
        TrayMenuIcon.Groups => "\uE902",
        TrayMenuIcon.StartAtLogin => "\uE7E8",
        TrayMenuIcon.CheckUpdates => "\uE895",
        TrayMenuIcon.Settings => "\uE713",
        TrayMenuIcon.Exit => "\uE8BB",
        _ => throw new ArgumentOutOfRangeException(nameof(icon)),
    };

    private nint CreateBitmap(string glyph)
    {
        var pixelCount = checked(_size * _size);
        var pixels = new byte[checked(pixelCount * 4)];
        var bitmapInfo = new BitmapInfo
        {
            Header = new BitmapInfoHeader
            {
                Size = (uint)Marshal.SizeOf<BitmapInfoHeader>(),
                Width = _size,
                Height = -_size,
                Planes = 1,
                BitCount = 32,
                Compression = 0,
                SizeImage = (uint)pixels.Length,
            },
        };

        var bitmap = NativeMethods.CreateDIBSection(
            nint.Zero,
            ref bitmapInfo,
            0,
            out var bitmapBits,
            nint.Zero,
            0);
        if (bitmap == nint.Zero)
        {
            return nint.Zero;
        }
        if (bitmapBits == nint.Zero)
        {
            NativeMethods.DeleteObject(bitmap);
            return nint.Zero;
        }

        nint deviceContext = nint.Zero;
        nint font = nint.Zero;
        nint previousBitmap = nint.Zero;
        nint previousFont = nint.Zero;
        var completed = false;
        try
        {
            Marshal.Copy(pixels, 0, bitmapBits, pixels.Length);
            deviceContext = NativeMethods.CreateCompatibleDC(nint.Zero);
            if (deviceContext == nint.Zero)
            {
                return nint.Zero;
            }

            previousBitmap = NativeMethods.SelectObject(deviceContext, bitmap);
            font = NativeMethods.CreateFont(
                -Math.Max(12, _size - 2),
                0,
                0,
                0,
                400,
                0,
                0,
                0,
                1,
                0,
                0,
                4,
                0,
                "Segoe MDL2 Assets");
            if (font == nint.Zero)
            {
                return nint.Zero;
            }

            previousFont = NativeMethods.SelectObject(deviceContext, font);
            NativeMethods.SetBkMode(deviceContext, 1);
            NativeMethods.SetTextColor(deviceContext, 0x00ffffff);
            var bounds = new NativeRect(0, 0, _size, _size);
            NativeMethods.DrawText(
                deviceContext,
                glyph,
                glyph.Length,
                ref bounds,
                0x00000001 | 0x00000004 | 0x00000020 | 0x00000800);

            Marshal.Copy(bitmapBits, pixels, 0, pixels.Length);
            ApplyMenuTextColor(pixels, NativeMethods.GetSysColor(MenuTextColor));
            if (!HasVisiblePixels(pixels))
            {
                return nint.Zero;
            }
            Marshal.Copy(pixels, 0, bitmapBits, pixels.Length);
            completed = true;
            return bitmap;
        }
        finally
        {
            if (previousFont != nint.Zero)
            {
                NativeMethods.SelectObject(deviceContext, previousFont);
            }
            if (previousBitmap != nint.Zero)
            {
                NativeMethods.SelectObject(deviceContext, previousBitmap);
            }
            if (font != nint.Zero)
            {
                NativeMethods.DeleteObject(font);
            }
            if (deviceContext != nint.Zero)
            {
                NativeMethods.DeleteDC(deviceContext);
            }
            if (!completed && bitmap != nint.Zero)
            {
                NativeMethods.DeleteObject(bitmap);
            }
        }
    }

    internal static void ApplyMenuTextColor(byte[] pixels, uint color)
    {
        ArgumentNullException.ThrowIfNull(pixels);
        if (pixels.Length % 4 != 0)
        {
            throw new ArgumentException("BGRA pixels must contain complete pixels.", nameof(pixels));
        }

        var red = (byte)(color & 0xff);
        var green = (byte)((color >> 8) & 0xff);
        var blue = (byte)((color >> 16) & 0xff);
        for (var index = 0; index < pixels.Length; index += 4)
        {
            var coverage = Math.Max(pixels[index], Math.Max(pixels[index + 1], pixels[index + 2]));
            pixels[index] = (byte)(blue * coverage / 255);
            pixels[index + 1] = (byte)(green * coverage / 255);
            pixels[index + 2] = (byte)(red * coverage / 255);
            pixels[index + 3] = coverage;
        }
    }

    private static bool HasVisiblePixels(byte[] pixels)
    {
        for (var index = 3; index < pixels.Length; index += 4)
        {
            if (pixels[index] > 0)
            {
                return true;
            }
        }
        return false;
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
    private struct NativeRect(int left, int top, int right, int bottom)
    {
        public int Left = left;
        public int Top = top;
        public int Right = right;
        public int Bottom = bottom;
    }

    private static class NativeMethods
    {
        [DllImport("gdi32.dll")]
        public static extern nint CreateDIBSection(
            nint deviceContext,
            ref BitmapInfo bitmapInfo,
            uint usage,
            out nint bits,
            nint section,
            uint offset);

        [DllImport("gdi32.dll")]
        public static extern nint CreateCompatibleDC(nint deviceContext);

        [DllImport("gdi32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool DeleteDC(nint deviceContext);

        [DllImport("gdi32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool DeleteObject(nint value);

        [DllImport("gdi32.dll")]
        public static extern nint SelectObject(nint deviceContext, nint value);

        [DllImport("gdi32.dll", EntryPoint = "CreateFontW", CharSet = CharSet.Unicode)]
        public static extern nint CreateFont(
            int height,
            int width,
            int escapement,
            int orientation,
            int weight,
            uint italic,
            uint underline,
            uint strikeOut,
            uint characterSet,
            uint outputPrecision,
            uint clipPrecision,
            uint quality,
            uint pitchAndFamily,
            string faceName);

        [DllImport("gdi32.dll")]
        public static extern int SetBkMode(nint deviceContext, int mode);

        [DllImport("gdi32.dll")]
        public static extern uint SetTextColor(nint deviceContext, uint color);

        [DllImport("user32.dll", EntryPoint = "DrawTextW", CharSet = CharSet.Unicode)]
        public static extern int DrawText(
            nint deviceContext,
            string text,
            int textLength,
            ref NativeRect rectangle,
            uint format);

        [DllImport("user32.dll")]
        public static extern uint GetSysColor(int index);
    }
}
