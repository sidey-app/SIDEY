using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.UI;
using Microsoft.Graphics.Canvas.UI.Xaml;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sidey.Core.Domain;
using Sidey.Platform.Windows;
using Windows.Foundation;

namespace Sidey.App.Controls;

public sealed partial class StoreProductArtwork : UserControl
{
    public static readonly DependencyProperty ProductKindProperty = DependencyProperty.Register(
        nameof(ProductKind), typeof(CommerceProductKind), typeof(StoreProductArtwork),
        new PropertyMetadata(CommerceProductKind.Character, OnProductChanged));
    public static readonly DependencyProperty CatalogItemIdProperty = DependencyProperty.Register(
        nameof(CatalogItemId), typeof(string), typeof(StoreProductArtwork),
        new PropertyMetadata(string.Empty, OnProductChanged));
    public static readonly DependencyProperty CharacterIdProperty = DependencyProperty.Register(
        nameof(CharacterId), typeof(string), typeof(StoreProductArtwork),
        new PropertyMetadata(PixelCharacterCatalog.FallbackId, OnProductChanged));

    private CanvasBitmap? _bitmap;
    private Rect _source;
    private int _generation;

    public StoreProductArtwork() => InitializeComponent();

    public CommerceProductKind ProductKind
    {
        get => (CommerceProductKind)GetValue(ProductKindProperty);
        set => SetValue(ProductKindProperty, value);
    }
    public string CatalogItemId
    {
        get => (string)GetValue(CatalogItemIdProperty);
        set => SetValue(CatalogItemIdProperty, value);
    }
    public string CharacterId
    {
        get => (string)GetValue(CharacterIdProperty);
        set => SetValue(CharacterIdProperty, value);
    }

    private static void OnProductChanged(DependencyObject sender, DependencyPropertyChangedEventArgs args)
    {
        _ = args;
        if (((StoreProductArtwork)sender).IsLoaded)
        {
            ((StoreProductArtwork)sender).BeginReload();
        }
    }

    private async void OnCreateResources(CanvasControl sender, CanvasCreateResourcesEventArgs args)
    {
        _ = args;
        await LoadAsync(sender);
    }

    private async void BeginReload() => await LoadAsync(ArtworkCanvas);

    private async Task LoadAsync(CanvasControl canvas)
    {
        int generation = Interlocked.Increment(ref _generation);
        string root = Path.Combine(SideyDeploymentPaths.DeploymentRoot(), "Assets");
        string path;
        Rect source;
        if (ProductKind == CommerceProductKind.Character)
        {
            PixelCharacterDefinition definition = PixelCharacterCatalog.Get(CharacterId);
            path = Path.Combine(root, definition.SpriteSheetResource.Replace('/', Path.DirectorySeparatorChar));
            source = new Rect(0, 0, definition.FrameWidth, definition.FrameHeight);
        }
        else if (ProductKind == CommerceProductKind.Bubble)
        {
            if (string.IsNullOrEmpty(CatalogItemId))
            {
                _bitmap?.Dispose();
                _bitmap = null;
                canvas.Invalidate();
                return;
            }
            path = Path.Combine(root, "Bubbles", CatalogItemId, "preview.png");
            source = new Rect(0, 0, 128, 48);
        }
        else
        {
            string throwableId = string.IsNullOrEmpty(CatalogItemId) ? "patch_soft_ball" : CatalogItemId;
            string preview = Path.Combine(root, "Throwables", throwableId, "preview.png");
            path = File.Exists(preview)
                ? preview
                : Path.Combine(root, "Throwables", throwableId, "sprite.png");
            source = File.Exists(preview) ? new Rect(0, 0, 176, 56) : new Rect(0, 0, 16, 16);
        }

        CanvasBitmap? loaded = null;
        try
        {
            loaded = await CanvasBitmap.LoadAsync(canvas, path);
            if (generation != Volatile.Read(ref _generation) || !IsLoaded)
            {
                loaded.Dispose();
                return;
            }
            _bitmap?.Dispose();
            _bitmap = loaded;
            _source = source;
            loaded = null;
            canvas.Invalidate();
        }
        catch
        {
            loaded?.Dispose();
        }
    }

    private void OnDraw(CanvasControl sender, CanvasDrawEventArgs args)
    {
        if (sender.ActualWidth <= 0 || sender.ActualHeight <= 0) return;
        if (_bitmap is null && ProductKind == CommerceProductKind.Bubble)
        {
            args.DrawingSession.FillRoundedRectangle(
                8, (float)(sender.ActualHeight / 2 - 18), (float)Math.Max(20, sender.ActualWidth - 16), 36,
                9, 9, Windows.UI.Color.FromArgb(245, 255, 255, 255));
            args.DrawingSession.DrawRoundedRectangle(
                8.5f, (float)(sender.ActualHeight / 2 - 17.5), (float)Math.Max(19, sender.ActualWidth - 17), 35,
                9, 9, Windows.UI.Color.FromArgb(50, 20, 23, 31), 1);
            return;
        }
        if (_bitmap is null) return;
        double maxWidth = ProductKind == CommerceProductKind.Character ? 96 : Math.Min(220, sender.ActualWidth - 16);
        double maxHeight = ProductKind == CommerceProductKind.Character ? 96 : Math.Min(96, sender.ActualHeight - 16);
        double scale = Math.Min(maxWidth / _source.Width, maxHeight / _source.Height);
        double width = _source.Width * scale;
        double height = _source.Height * scale;
        args.DrawingSession.DrawImage(
            _bitmap,
            new Rect((sender.ActualWidth - width) / 2, (sender.ActualHeight - height) / 2, width, height),
            _source,
            1f,
            CanvasImageInterpolation.NearestNeighbor);
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender; _ = args;
        Interlocked.Increment(ref _generation);
        _bitmap?.Dispose();
        _bitmap = null;
    }
}
