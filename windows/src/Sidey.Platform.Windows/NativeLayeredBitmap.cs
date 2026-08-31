using System.ComponentModel;
using System.Drawing;
using System.Runtime.InteropServices;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Gdi;
using Windows.Win32.UI.WindowsAndMessaging;

namespace Sidey.Platform.Windows;

/// <summary>
/// Owns one premultiplied BGRA DIB and presents it through UpdateLayeredWindow.
/// Instances are intentionally small and immutable so animation frames can be
/// prepared once instead of allocating or scaling on every 30 FPS tick.
/// </summary>
public sealed unsafe class NativeLayeredBitmap : IDisposable
{
    private const byte SourceOver = 0;
    private const byte SourceAlpha = 1;

    private readonly HWND _window;
    private readonly HDC _memoryDeviceContext;
    private readonly HBITMAP _bitmap;
    private readonly HGDIOBJ _previousObject;
    private bool _disposed;

    public NativeLayeredBitmap(
        nint windowHandle,
        int width,
        int height,
        ReadOnlySpan<byte> premultipliedBgra)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("Layered bitmap presentation requires Windows.");
        }

        if (windowHandle == 0)
        {
            throw new ArgumentOutOfRangeException(nameof(windowHandle));
        }

        if (width <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width));
        }

        if (height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(height));
        }

        var expectedByteCount = checked(width * height * 4);
        if (premultipliedBgra.Length != expectedByteCount)
        {
            throw new ArgumentException(
                $"Expected {expectedByteCount} BGRA bytes but received {premultipliedBgra.Length}.",
                nameof(premultipliedBgra));
        }

        _window = new HWND((void*)windowHandle);
        Width = width;
        Height = height;

        var screenDeviceContext = PInvoke.GetDC(HWND.Null);
        if (screenDeviceContext.IsNull)
        {
            throw LastWin32Exception("GetDC failed while preparing a layered bitmap.");
        }

        HDC memoryDeviceContext = default;
        HBITMAP bitmap = default;
        HGDIOBJ previousObject = default;
        try
        {
            memoryDeviceContext = PInvoke.CreateCompatibleDC(screenDeviceContext);
            if (memoryDeviceContext.IsNull)
            {
                throw LastWin32Exception("CreateCompatibleDC failed.");
            }

            var bitmapInfo = new BITMAPINFO
            {
                bmiHeader = new BITMAPINFOHEADER
                {
                    biSize = (uint)sizeof(BITMAPINFOHEADER),
                    biWidth = width,
                    biHeight = -height,
                    biPlanes = 1,
                    biBitCount = 32,
                    biCompression = 0, // BI_RGB
                    biSizeImage = (uint)expectedByteCount,
                },
            };
            void* destination;
            bitmap = PInvoke.CreateDIBSection(
                screenDeviceContext,
                &bitmapInfo,
                DIB_USAGE.DIB_RGB_COLORS,
                &destination,
                HANDLE.Null,
                0);
            if (bitmap.IsNull || destination is null)
            {
                throw LastWin32Exception("CreateDIBSection failed.");
            }

            fixed (byte* source = premultipliedBgra)
            {
                Buffer.MemoryCopy(source, destination, expectedByteCount, expectedByteCount);
            }

            previousObject = PInvoke.SelectObject(memoryDeviceContext, bitmap);
            if (previousObject.IsNull || (nint)previousObject.Value == -1)
            {
                throw LastWin32Exception("SelectObject failed for the layered bitmap.");
            }

            _memoryDeviceContext = memoryDeviceContext;
            _bitmap = bitmap;
            _previousObject = previousObject;
        }
        catch
        {
            if (!bitmap.IsNull)
            {
                PInvoke.DeleteObject(bitmap);
            }

            if (!memoryDeviceContext.IsNull)
            {
                PInvoke.DeleteDC(memoryDeviceContext);
            }

            throw;
        }
        finally
        {
            PInvoke.ReleaseDC(HWND.Null, screenDeviceContext);
        }
    }

    public int Width { get; }
    public int Height { get; }

    public void Present(int screenX, int screenY)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var screenDeviceContext = PInvoke.GetDC(HWND.Null);
        if (screenDeviceContext.IsNull)
        {
            throw LastWin32Exception("GetDC failed while presenting a layered bitmap.");
        }

        try
        {
            var destination = new Point(screenX, screenY);
            var size = new SIZE(Width, Height);
            var source = Point.Empty;
            var blend = new BLENDFUNCTION
            {
                BlendOp = SourceOver,
                BlendFlags = 0,
                SourceConstantAlpha = byte.MaxValue,
                AlphaFormat = SourceAlpha,
            };
            if (!PInvoke.UpdateLayeredWindow(
                    _window,
                    screenDeviceContext,
                    destination,
                    size,
                    _memoryDeviceContext,
                    source,
                    default,
                    blend,
                    UPDATE_LAYERED_WINDOW_FLAGS.ULW_ALPHA))
            {
                throw LastWin32Exception("UpdateLayeredWindow failed.");
            }
        }
        finally
        {
            PInvoke.ReleaseDC(HWND.Null, screenDeviceContext);
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        PInvoke.SelectObject(_memoryDeviceContext, _previousObject);
        PInvoke.DeleteObject(_bitmap);
        PInvoke.DeleteDC(_memoryDeviceContext);
    }

    private static Win32Exception LastWin32Exception(string message) =>
        new(Marshal.GetLastPInvokeError(), message);
}
