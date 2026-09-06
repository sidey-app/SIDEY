using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Sidey.Platform.Windows;
using Windows.UI;

namespace Sidey.App.Controls;

public sealed partial class StorePreviewStage : UserControl
{
    private const double StageWidth = 540;
    private const double CharacterTop = 208;
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(1000d / 30d) };
    private readonly Stopwatch _clock = new();
    private readonly Dictionary<string, ImageSource> _characters = new(StringComparer.Ordinal);
    private ImageSource? _projectile;
    private ImageSource? _emitter;
    private double _manualThrowStarted = -10;
    private bool _resourcesLoaded;
    private bool _loading;

    public StorePreviewStage(CommerceProductKind kind, string catalogItemId, string characterId)
    {
        InitializeComponent();
        ProductKind = kind;
        CatalogItemId = catalogItemId;
        CharacterId = PixelCharacterCatalog.NormalizeId(characterId);
        _timer.Tick += OnTimerTick;
        BuildPlatform();
    }

    public CommerceProductKind ProductKind { get; }
    public string CatalogItemId { get; }
    public string CharacterId { get; }

    private async void OnLoaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        await InitializeAsync();

        StartAnimation();
    }

    public async Task InitializeAsync()
    {
        if (!_resourcesLoaded && !_loading)
        {
            await LoadResourcesAsync();
        }
    }

    public void StartAnimation()
    {
        if (!_resourcesLoaded)
        {
            return;
        }

        _clock.Start();
        _timer.Start();
        UpdateScene();
    }

    public void StopAnimation()
    {
        _timer.Stop();
        _clock.Stop();
    }

    private async Task LoadResourcesAsync()
    {
        _loading = true;
        try
        {
            string root = Path.Combine(SideyDeploymentPaths.DeploymentRoot(), "Assets");
            string leftId = ProductKind == CommerceProductKind.Character
                ? CharacterId
                : PixelCharacterCatalog.FallbackId;
            foreach (string id in new[] { leftId, "pixel_cat" }.Distinct(StringComparer.Ordinal))
            {
                PixelCharacterDefinition definition = PixelCharacterCatalog.Get(id);
                string path = Path.Combine(
                    root,
                    definition.SpriteSheetResource.Replace('/', Path.DirectorySeparatorChar));
                _characters[id] = await StorePreviewImageLoader.LoadFrameAsync(
                    path,
                    checked((uint)definition.FrameWidth),
                    checked((uint)definition.FrameHeight),
                    frame: 0,
                    renderedWidth: 48,
                    renderedHeight: 48);
            }

            if (ProductKind == CommerceProductKind.Bubble)
            {
                BubbleDecoration.Source = await StorePreviewImageLoader.LoadFrameAsync(
                    Path.Combine(root, "Bubbles", CatalogItemId, "decoration.png"),
                    frameWidth: 16,
                    frameHeight: 16,
                    frame: 0,
                    renderedWidth: 16,
                    renderedHeight: 16);
                ApplyBubbleColors();
            }
            else
            {
                string objectId = ProductKind == CommerceProductKind.Throwable
                    ? CatalogItemId
                    : StoreProductArtwork.SignatureObject(CharacterId);
                string objectPath = Path.Combine(root, "Throwables", objectId, "sprite.png");
                _projectile = await StorePreviewImageLoader.LoadFrameAsync(
                    objectPath,
                    frameWidth: 16,
                    frameHeight: 16,
                    frame: 0,
                    renderedWidth: 32,
                    renderedHeight: 32);

                if (objectId == "throwable_toy_cannon")
                {
                    string emitterPath = Path.Combine(root, "Throwables", objectId, "emitter.png");
                    _emitter = await StorePreviewImageLoader.LoadFrameAsync(
                        emitterPath,
                        frameWidth: 24,
                        frameHeight: 24,
                        frame: 2,
                        renderedWidth: 48,
                        renderedHeight: 48);
                }
            }

            _resourcesLoaded = true;
            LoadingRing.IsActive = false;
            LoadingRing.Visibility = Visibility.Collapsed;
            SceneCanvas.Visibility = Visibility.Visible;
            UpdateScene();
        }
        catch
        {
            LoadingRing.IsActive = false;
            LoadingRing.Visibility = Visibility.Collapsed;
            ErrorText.Text = I18n.Get("store.previewUnavailable");
            ErrorText.Visibility = Visibility.Visible;
        }
        finally
        {
            _loading = false;
        }
    }

    private void OnTimerTick(object? sender, object args)
    {
        _ = sender;
        _ = args;
        UpdateScene();
    }

    private void UpdateScene()
    {
        if (!_resourcesLoaded)
        {
            return;
        }

        double elapsed = _clock.IsRunning ? _clock.Elapsed.TotalSeconds : 0;
        string leftId = ProductKind == CommerceProductKind.Character
            ? CharacterId
            : PixelCharacterCatalog.FallbackId;
        LeftCharacter.Source = _characters[leftId];
        RightCharacter.Source = _characters["pixel_cat"];

        double drift = ProductKind == CommerceProductKind.Character
            ? Math.Sin(elapsed * 0.9) * 30
            : 0;
        double leftX = (ProductKind == CommerceProductKind.Bubble ? 118 : 92) + drift;
        double rightX = (ProductKind == CommerceProductKind.Bubble ? 374 : 400) - drift;
        PositionCharacters(leftX, rightX);

        if (ProductKind == CommerceProductKind.Bubble)
        {
            UpdateBubble(elapsed, leftX, rightX);
            ProjectileImage.Visibility = Visibility.Collapsed;
            EmitterImage.Visibility = Visibility.Collapsed;
            return;
        }

        BubblePreview.Visibility = Visibility.Collapsed;
        if (ProductKind == CommerceProductKind.Throwable)
        {
            double sequenceTime = Math.Max(0, elapsed - 0.35);
            int sequenceIndex = (int)Math.Floor(sequenceTime);
            UpdateThrow(sequenceTime - sequenceIndex, leftX, rightX, sequenceIndex % 2 == 0);
        }
        else
        {
            UpdateThrow(elapsed - _manualThrowStarted, leftX, rightX, leftToRight: true);
        }
    }

    private void PositionCharacters(double leftX, double rightX)
    {
        Canvas.SetLeft(LeftCharacter, leftX);
        Canvas.SetTop(LeftCharacter, CharacterTop);
        Canvas.SetLeft(RightCharacter, rightX);
        Canvas.SetTop(RightCharacter, CharacterTop);
        Canvas.SetLeft(LeftNameplate, leftX - 10);
        Canvas.SetLeft(RightNameplate, rightX - 10);
    }

    private void UpdateBubble(double elapsed, double leftX, double rightX)
    {
        double phase = elapsed % 6;
        bool fromLeft = phase < 3;
        double local = phase % 3;
        bool typing = local < 1;
        BubbleText.Text = typing
            ? new string('.', 1 + ((int)(local * 3) % 3))
            : fromLeft ? "오늘도 같이 있자!" : "곰도리탕 어때?";
        double bubbleWidth = typing ? 54 : 142;
        BubblePreview.Width = bubbleWidth;
        BubbleBody.Width = bubbleWidth;
        BubbleDecoration.Visibility = typing ? Visibility.Collapsed : Visibility.Visible;
        Canvas.SetLeft(BubbleTail, fromLeft ? 18 : bubbleWidth - 32);
        Canvas.SetLeft(
            BubblePreview,
            fromLeft ? leftX - 4 : rightX + 48 - BubblePreview.Width + 4);
        BubblePreview.Visibility = Visibility.Visible;
    }

    private void UpdateThrow(
        double local,
        double leftX,
        double rightX,
        bool leftToRight)
    {
        if (local < 0 || local > 1)
        {
            ProjectileImage.Visibility = Visibility.Collapsed;
            EmitterImage.Visibility = Visibility.Collapsed;
            return;
        }

        double progress = Math.Clamp((local - 0.12) / 0.72, 0, 1);
        double startX = leftToRight ? leftX + 38 : rightX - 22;
        double endX = leftToRight ? rightX - 10 : leftX + 38;
        double x = startX + ((endX - startX) * progress);
        double y = 218 - (Math.Sin(progress * Math.PI) * 72);
        ProjectileImage.Source = _projectile;
        ProjectileScale.ScaleX = leftToRight ? 1 : -1;
        Canvas.SetLeft(ProjectileImage, x);
        Canvas.SetTop(ProjectileImage, y);
        ProjectileImage.Visibility = Visibility.Visible;

        if (_emitter is not null && local < 0.4)
        {
            EmitterImage.Source = _emitter;
            Canvas.SetLeft(EmitterImage, leftToRight ? leftX : rightX);
            Canvas.SetTop(EmitterImage, CharacterTop);
            EmitterImage.Visibility = Visibility.Visible;
        }
        else
        {
            EmitterImage.Visibility = Visibility.Collapsed;
        }
    }

    private void ApplyBubbleColors()
    {
        (Color background, Color foreground) = CatalogItemId switch
        {
            "bubble_bunny_pink" =>
                (Color.FromArgb(255, 0xF7, 0xA9, 0xB8), Color.FromArgb(255, 0x1C, 0x1F, 0x29)),
            "bubble_butter_chick" =>
                (Color.FromArgb(255, 0xFF, 0xE3, 0x8A), Color.FromArgb(255, 0x1C, 0x1F, 0x29)),
            _ =>
                (Color.FromArgb(255, 0x40, 0x3A, 0x78), Color.FromArgb(255, 0xFF, 0xF7, 0xE8)),
        };
        var backgroundBrush = new SolidColorBrush(background);
        BubbleBody.Background = backgroundBrush;
        BubbleTail.Fill = backgroundBrush;
        BubbleText.Foreground = new SolidColorBrush(foreground);
    }

    private void BuildPlatform()
    {
        var baseBrush = new SolidColorBrush(Color.FromArgb(255, 0xB8, 0xBA, 0xBF));
        var alternateBrush = new SolidColorBrush(Color.FromArgb(255, 0xCD, 0xD0, 0xD3));
        PlatformCanvas.Background = baseBrush;
        const int pixel = 4;
        for (int row = 0; row < 6; row += 2)
        {
            for (int column = 0; column < StageWidth / pixel; column++)
            {
                if ((column % 2 == 0) == (row % 4 == 0))
                {
                    var tile = new Microsoft.UI.Xaml.Shapes.Rectangle
                    {
                        Width = pixel,
                        Height = pixel,
                        Fill = alternateBrush,
                    };
                    Canvas.SetLeft(tile, column * pixel);
                    Canvas.SetTop(tile, row * pixel);
                    PlatformCanvas.Children.Add(tile);
                }
            }
        }
    }

    private void OnTapped(object sender, TappedRoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (ProductKind == CommerceProductKind.Character && _resourcesLoaded)
        {
            _manualThrowStarted = _clock.Elapsed.TotalSeconds;
            UpdateScene();
        }
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
    }
}
