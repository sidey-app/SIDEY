using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Sidey.Core.Domain;
using Sidey.Platform.Windows;

namespace Sidey.App.Controls;

public sealed partial class PixelCharacterPreview : UserControl
{
    public static readonly DependencyProperty CharacterIdProperty = DependencyProperty.Register(
        nameof(CharacterId),
        typeof(string),
        typeof(PixelCharacterPreview),
        new PropertyMetadata(PixelCharacterCatalog.FallbackId, OnCharacterIdChanged));

    private string? _loadedCharacterId;
    private uint _loadedWidth;
    private uint _loadedHeight;
    private int _loadGeneration;
    private CancellationTokenSource? _loadCancellation;

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
            preview.BeginReloadIfNeeded();
        }
    }

    private void OnLoaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        BeginReloadIfNeeded();
    }

    private void OnSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        BeginReloadIfNeeded();
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        CancelPendingLoad();
        Interlocked.Increment(ref _loadGeneration);
        PreviewImage.Source = null;
        _loadedCharacterId = null;
        _loadedWidth = 0;
        _loadedHeight = 0;
    }

    private void BeginReloadIfNeeded()
    {
        if (!IsLoaded || ActualWidth <= 0 || ActualHeight <= 0)
        {
            return;
        }

        string characterId = PixelCharacterCatalog.NormalizeId(CharacterId);
        uint width = checked((uint)Math.Max(1, Math.Round(ActualWidth)));
        uint height = checked((uint)Math.Max(1, Math.Round(ActualHeight)));
        if (_loadedCharacterId == characterId && _loadedWidth == width && _loadedHeight == height)
        {
            return;
        }

        CancelPendingLoad();
        var cancellation = new CancellationTokenSource();
        _loadCancellation = cancellation;
        _ = LoadSpriteFrameAsync(characterId, width, height, cancellation);
    }

    private async Task LoadSpriteFrameAsync(
        string characterId,
        uint width,
        uint height,
        CancellationTokenSource cancellation)
    {
        int generation = Interlocked.Increment(ref _loadGeneration);
        PixelCharacterDefinition definition = PixelCharacterCatalog.Get(characterId);
        string path = Path.Combine(
            SideyDeploymentPaths.DeploymentRoot(),
            "Assets",
            definition.SpriteSheetResource.Replace('/', Path.DirectorySeparatorChar));

        try
        {
            ImageSource source = await StorePreviewImageLoader.LoadFrameAsync(
                path,
                checked((uint)definition.FrameWidth),
                checked((uint)definition.FrameHeight),
                frame: 0,
                renderedWidth: width,
                renderedHeight: height,
                cancellation.Token);
            if (generation != Volatile.Read(ref _loadGeneration)
                || !IsLoaded
                || !StringComparer.Ordinal.Equals(
                    characterId,
                    PixelCharacterCatalog.NormalizeId(CharacterId)))
            {
                return;
            }

            PreviewImage.Source = source;
            _loadedCharacterId = characterId;
            _loadedWidth = width;
            _loadedHeight = height;
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
        }
        catch
        {
            if (generation == Volatile.Read(ref _loadGeneration) && IsLoaded)
            {
                PreviewImage.Source = null;
                _loadedCharacterId = null;
                _loadedWidth = 0;
                _loadedHeight = 0;
            }
        }
        finally
        {
            if (ReferenceEquals(_loadCancellation, cancellation))
            {
                _loadCancellation = null;
                cancellation.Dispose();
            }
        }
    }

    private void CancelPendingLoad()
    {
        CancellationTokenSource? cancellation = _loadCancellation;
        _loadCancellation = null;
        if (cancellation is null)
        {
            return;
        }

        cancellation.Cancel();
        cancellation.Dispose();
    }
}
