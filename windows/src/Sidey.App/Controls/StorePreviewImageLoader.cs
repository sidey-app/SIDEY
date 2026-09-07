using System.Runtime.CompilerServices;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;

namespace Sidey.App.Controls;

internal static class StorePreviewImageLoader
{
    private static readonly ConditionalWeakTable<ImageSource, SoftwareBitmap> BitmapLifetimes = new();

    public static async Task<ImageSource> LoadFrameAsync(
        string path,
        uint frameWidth,
        uint frameHeight,
        int frame,
        uint renderedWidth,
        uint renderedHeight,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        using IRandomAccessStream stream = await FileRandomAccessStream.OpenAsync(
            path,
            FileAccessMode.Read);
        cancellationToken.ThrowIfCancellationRequested();
        BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);
        uint scaledSheetWidth = checked((uint)Math.Round(
            decoder.PixelWidth * ((double)renderedWidth / frameWidth)));
        uint scaledSheetHeight = checked((uint)Math.Round(
            decoder.PixelHeight * ((double)renderedHeight / frameHeight)));
        var transform = new BitmapTransform
        {
            Bounds = new BitmapBounds
            {
                X = checked((uint)Math.Max(0, frame)) * renderedWidth,
                Y = 0,
                Width = renderedWidth,
                Height = renderedHeight,
            },
            ScaledWidth = scaledSheetWidth,
            ScaledHeight = scaledSheetHeight,
            InterpolationMode = BitmapInterpolationMode.NearestNeighbor,
        };
        SoftwareBitmap? bitmap = null;
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            bitmap = await decoder.GetSoftwareBitmapAsync(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Premultiplied,
                transform,
                ExifOrientationMode.IgnoreExifOrientation,
                ColorManagementMode.DoNotColorManage);
            cancellationToken.ThrowIfCancellationRequested();
            var source = new SoftwareBitmapSource();
            await source.SetBitmapAsync(bitmap);
            cancellationToken.ThrowIfCancellationRequested();
            BitmapLifetimes.Add(source, bitmap);
            bitmap = null;
            return source;
        }
        finally
        {
            bitmap?.Dispose();
        }
    }

    public static async Task<ImageSource> LoadWholeAsync(
        string path,
        uint sourceWidth,
        uint sourceHeight,
        CancellationToken cancellationToken = default) =>
        await LoadFrameAsync(
            path,
            sourceWidth,
            sourceHeight,
            frame: 0,
            sourceWidth,
            sourceHeight,
            cancellationToken);
}
