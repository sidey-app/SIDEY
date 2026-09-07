using System.Numerics;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;

namespace Sidey.App.Controls;

internal sealed class PixelFrameSurface(LoadedImageSurface surface) : IDisposable
{
    internal LoadedImageSurface Surface { get; } = surface;
    public void Dispose() => Surface.Dispose();
}

// Keep a decoded GPU surface resident and select it synchronously. Unlike Image
// source replacement this does not schedule an asynchronous frame presentation.
public sealed class NearestPixelImage : Grid
{
    private PixelFrameSurface? _source;
    private SpriteVisual? _visual;
    private CompositionSurfaceBrush? _brush;

    public NearestPixelImage()
    {
        IsHitTestVisible = false;
        Loaded += (_, _) => Attach();
        Unloaded += (_, _) => Detach();
        SizeChanged += (_, _) => UpdateSize();
    }

    internal PixelFrameSurface? Source
    {
        get => _source;
        set
        {
            _source = value;
            if (_brush is not null) _brush.Surface = value?.Surface;
        }
    }

    internal bool IsNearestReady => _brush?.Surface is not null
        && _brush.BitmapInterpolationMode == CompositionBitmapInterpolationMode.NearestNeighbor;

    private void Attach()
    {
        if (_visual is not null) return;
        var compositor = ElementCompositionPreview.GetElementVisual(this).Compositor;
        _brush = compositor.CreateSurfaceBrush(_source?.Surface);
        _brush.BitmapInterpolationMode = CompositionBitmapInterpolationMode.NearestNeighbor;
        _brush.Stretch = CompositionStretch.Fill;
        _visual = compositor.CreateSpriteVisual();
        _visual.Brush = _brush;
        UpdateSize();
        ElementCompositionPreview.SetElementChildVisual(this, _visual);
    }

    private void UpdateSize()
    {
        if (_visual is not null) _visual.Size = new Vector2((float)ActualWidth, (float)ActualHeight);
    }

    private void Detach()
    {
        ElementCompositionPreview.SetElementChildVisual(this, null);
        _visual?.Dispose();
        _visual = null;
        _brush?.Dispose();
        _brush = null;
    }
}
