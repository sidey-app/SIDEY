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

    internal static void ReleaseFrame(ImageSource source)
    {
        if (BitmapLifetimes.TryGetValue(source, out var bitmap))
        {
            BitmapLifetimes.Remove(source);
            bitmap.Dispose();
        }
        if (source is IDisposable disposable)
            disposable.Dispose();
    }

    internal static async Task<PixelFrameSurface> LoadPixelFrameAsync(
        string path, uint frameWidth, uint frameHeight, int frame,
        uint renderedWidth, uint renderedHeight, CancellationToken cancellationToken)
    {
        var image = await LoadFrameAsync(path, frameWidth, frameHeight, frame,
            renderedWidth, renderedHeight, cancellationToken);
        var bitmap = BitmapLifetimes.GetValue(image, _ => throw new InvalidOperationException("Missing decoded frame."));
        using var stream = new InMemoryRandomAccessStream();
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
        encoder.SetSoftwareBitmap(bitmap);
        await encoder.FlushAsync();
        cancellationToken.ThrowIfCancellationRequested();
        stream.Seek(0);
        var surface = LoadedImageSurface.StartLoadFromStream(stream);
        var completion = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        void OnCompleted(LoadedImageSurface sender, LoadedImageSourceLoadCompletedEventArgs args)
        {
            if (args.Status == LoadedImageSourceLoadStatus.Success)
                completion.TrySetResult(true);
            else
                completion.TrySetException(new InvalidOperationException($"Pixel surface load failed: {args.Status}"));
        }
        surface.LoadCompleted += OnCompleted;
        try
        {
            await completion.Task.WaitAsync(TimeSpan.FromSeconds(15), cancellationToken);
            surface.LoadCompleted -= OnCompleted;
            return new PixelFrameSurface(surface);
        }
        catch
        {
            surface.LoadCompleted -= OnCompleted;
            surface.Dispose();
            throw;
        }
    }

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
