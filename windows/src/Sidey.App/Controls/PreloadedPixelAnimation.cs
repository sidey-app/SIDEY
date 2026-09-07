using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;

namespace Sidey.App.Controls;

// Every native Image retains its decoded frame. Animation changes only opacity,
// never the image source or a custom composition surface during flight.
public sealed class PreloadedPixelAnimation : Grid
{
    private readonly List<Image> _frames = [];
    private int _frame = -1;

    public PreloadedPixelAnimation() => IsHitTestVisible = false;

    internal ImageSource? Source => _frame >= 0 ? _frames[_frame].Source : null;
    internal bool IsFrameReady => _frame >= 0 && _frames[_frame].Source is not null
        && _frames[_frame].ActualWidth > 0 && _frames[_frame].ActualHeight > 0;

    internal void SetFrames(IEnumerable<ImageSource> frames)
    {
        ClearFrames();
        foreach (var source in frames)
        {
            var image = new Image { Source = source, Stretch = Stretch.None, Opacity = 0 };
            _frames.Add(image);
            Children.Add(image);
        }
    }

    internal void ShowFrame(int frame)
    {
        if (frame == _frame)
            return;
        if (_frame >= 0)
            _frames[_frame].Opacity = 0;
        _frame = frame;
        _frames[frame].Opacity = 1;
    }

    internal void ClearFrames()
    {
        foreach (var image in _frames)
            image.Source = null;
        Children.Clear();
        _frames.Clear();
        _frame = -1;
    }

    internal async Task VerifyRenderedFrameAsync()
    {
        if (!IsFrameReady)
            throw new InvalidOperationException("Preview frame has no arranged image.");
        var rendered = new RenderTargetBitmap();
        await rendered.RenderAsync(_frames[_frame]);
        byte[] pixels = (await rendered.GetPixelsAsync()).ToArray();
        int visiblePixels = 0;
        for (int offset = 3; offset < pixels.Length; offset += 4)
            if (pixels[offset] > 0)
                visiblePixels++;
        if (visiblePixels < 8)
            throw new InvalidOperationException("Preview frame rendered without visible pixels.");
    }
}
