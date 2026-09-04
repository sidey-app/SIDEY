using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.UI;
using Microsoft.Graphics.Canvas.UI.Xaml;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sidey.Core.Domain;
using Sidey.Platform.Windows;
using Windows.Foundation;

namespace Sidey.App.Controls;

public sealed partial class PixelCharacterPreview : UserControl
{
    public static readonly DependencyProperty CharacterIdProperty = DependencyProperty.Register(
        nameof(CharacterId),
        typeof(string),
        typeof(PixelCharacterPreview),
        new PropertyMetadata(PixelCharacterCatalog.FallbackId, OnCharacterIdChanged));

    private CanvasBitmap? _spriteSheet;
    private string? _loadedCharacterId;
    private int _loadGeneration;

    public PixelCharacterPreview()
    {
        InitializeComponent();
    }

    public string CharacterId
    {
        get => (string)GetValue(CharacterIdProperty);
        set => SetValue(CharacterIdProperty, value);
    }

    private static void OnCharacterIdChanged(
        DependencyObject dependencyObject,
        DependencyPropertyChangedEventArgs args)
    {
        _ = args;
        var preview = (PixelCharacterPreview)dependencyObject;
        if (preview.IsLoaded)
        {
            preview.BeginReload();
        }
    }

    private async void OnCreateResources(
        CanvasControl sender,
        CanvasCreateResourcesEventArgs args)
    {
        _ = args;
        await LoadSpriteSheetAsync(sender);
    }

    private void OnLoaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (_loadedCharacterId != PixelCharacterCatalog.NormalizeId(CharacterId))
        {
            BeginReload();
        }
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        Interlocked.Increment(ref _loadGeneration);
        _spriteSheet?.Dispose();
        _spriteSheet = null;
        _loadedCharacterId = null;
    }

    private void OnDraw(CanvasControl sender, CanvasDrawEventArgs args)
    {
        if (_spriteSheet is null
            || _loadedCharacterId != PixelCharacterCatalog.NormalizeId(CharacterId)
            || sender.ActualWidth <= 0
            || sender.ActualHeight <= 0)
        {
            return;
        }

        PixelCharacterDefinition definition = PixelCharacterCatalog.Get(_loadedCharacterId);
        args.DrawingSession.DrawImage(
            _spriteSheet,
            new Rect(0, 0, sender.ActualWidth, sender.ActualHeight),
            new Rect(0, 0, definition.FrameWidth, definition.FrameHeight),
            1f,
            CanvasImageInterpolation.NearestNeighbor);
    }

    private async void BeginReload()
    {
        await LoadSpriteSheetAsync(PreviewCanvas);
    }

    private async Task LoadSpriteSheetAsync(CanvasControl resourceCreator)
    {
        int generation = Interlocked.Increment(ref _loadGeneration);
        string characterId = PixelCharacterCatalog.NormalizeId(CharacterId);
        PixelCharacterDefinition definition = PixelCharacterCatalog.Get(characterId);
        string path = Path.Combine(
            SideyDeploymentPaths.DeploymentRoot(),
            "Assets",
            definition.SpriteSheetResource.Replace('/', Path.DirectorySeparatorChar));

        CanvasBitmap? loaded = null;
        try
        {
            loaded = await CanvasBitmap.LoadAsync(resourceCreator, path);
            if (generation != Volatile.Read(ref _loadGeneration) || !IsLoaded)
            {
                loaded.Dispose();
                return;
            }

            CanvasBitmap? previous = _spriteSheet;
            _spriteSheet = loaded;
            _loadedCharacterId = characterId;
            loaded = null;
            previous?.Dispose();
            resourceCreator.Invalidate();
        }
        catch (Exception)
        {
            loaded?.Dispose();
        }
    }
}
