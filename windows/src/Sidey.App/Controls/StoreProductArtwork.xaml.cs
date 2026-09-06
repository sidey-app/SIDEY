using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Sidey.Core.Domain;
using Sidey.Platform.Windows;

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

    private static void OnProductChanged(
        DependencyObject sender,
        DependencyPropertyChangedEventArgs args)
    {
        _ = args;
        var artwork = (StoreProductArtwork)sender;
        if (artwork.IsLoaded)
        {
            artwork.BeginReload();
        }
    }

    private void OnLoaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        BeginReload();
    }

    private async void BeginReload()
    {
        int generation = Interlocked.Increment(ref _generation);
        PreviewImage.Source = null;
        DefaultBubblePreview.Visibility = Visibility.Collapsed;
        try
        {
            ImageSource? source = await LoadPreviewAsync();
            if (generation != Volatile.Read(ref _generation) || !IsLoaded)
            {
                return;
            }

            PreviewImage.Source = source;
        }
        catch
        {
            if (generation == Volatile.Read(ref _generation))
            {
                PreviewImage.Source = null;
            }
        }
    }

    private async Task<ImageSource?> LoadPreviewAsync()
    {
        string root = Path.Combine(SideyDeploymentPaths.DeploymentRoot(), "Assets");
        if (ProductKind == CommerceProductKind.Character)
        {
            PixelCharacterDefinition definition = PixelCharacterCatalog.Get(CharacterId);
            string path = Path.Combine(
                root,
                definition.SpriteSheetResource.Replace('/', Path.DirectorySeparatorChar));
            return await StorePreviewImageLoader.LoadFrameAsync(
                path,
                checked((uint)definition.FrameWidth),
                checked((uint)definition.FrameHeight),
                frame: 0,
                renderedWidth: 72,
                renderedHeight: 72);
        }

        if (ProductKind == CommerceProductKind.Bubble)
        {
            if (string.IsNullOrEmpty(CatalogItemId))
            {
                DefaultBubblePreview.Visibility = Visibility.Visible;
                return null;
            }

            return await StorePreviewImageLoader.LoadWholeAsync(
                Path.Combine(root, "Bubbles", CatalogItemId, "preview.png"),
                sourceWidth: 128,
                sourceHeight: 48);
        }

        string throwableId = string.IsNullOrEmpty(CatalogItemId)
            ? SignatureObject(CharacterId)
            : CatalogItemId;
        if (throwableId == "throwable_toy_cannon")
        {
            return await StorePreviewImageLoader.LoadWholeAsync(
                Path.Combine(root, "Throwables", throwableId, "preview.png"),
                sourceWidth: 176,
                sourceHeight: 56);
        }

        return await StorePreviewImageLoader.LoadFrameAsync(
            Path.Combine(root, "Throwables", throwableId, "sprite.png"),
            frameWidth: 16,
            frameHeight: 16,
            frame: 0,
            renderedWidth: 48,
            renderedHeight: 48);
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        Interlocked.Increment(ref _generation);
        PreviewImage.Source = null;
    }

    internal static string SignatureObject(string characterId) => characterId switch
    {
        "pixel_guinea_pig" => "mini_paprika",
        "pixel_monkey" => "banana",
        "pixel_chinchilla" => "dust_bath_pouch",
        "pixel_starlight_upalupa" => "starlight_orb",
        _ => "patch_soft_ball",
    };
}
