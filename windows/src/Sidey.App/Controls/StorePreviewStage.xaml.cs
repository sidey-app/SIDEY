using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Sidey.Core.Overlay;
using Sidey.Platform.Windows;
using Windows.UI;

namespace Sidey.App.Controls;

public sealed partial class StorePreviewStage : UserControl
{
    private const double StageWidth = 540;
    private const double PlatformTop = 256;
    private const double RenderedCharacterSize = 48;
    private const double RenderedFootBaseline = 6;
    private const double CharacterTop = PlatformTop - RenderedCharacterSize + RenderedFootBaseline;
    private const double PreviewWallInset = 12;
    private const double WalkFrameSeconds = 0.16;
    private static readonly IReadOnlyList<RectD> NoAvoidanceRects = Array.Empty<RectD>();
    private static readonly IReadOnlySet<Guid> NoStoppedIds = new HashSet<Guid>();
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(1000d / 30d) };
    private readonly Stopwatch _clock = new();
    private readonly Dictionary<string, IReadOnlyList<ImageSource>> _characters = new(StringComparer.Ordinal);
    private readonly EdgeTrackGeometry _movementGeometry = new(
        new RectD(0, 0, StageWidth, 280),
        OverlayEdge.Bottom,
        tangentExtent: RenderedCharacterSize + (PreviewWallInset * 2));
    private readonly List<PixelMovementAgent> _movementAgents = [];
    private readonly PixelMovementScratch _movementScratch = new();
    private readonly Random _random = new(0x51DE59);
    private ImageSource? _projectile;
    private ImageSource? _emitter;
    private double _manualThrowStarted = -10;
    private double _lastSceneElapsed;
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
        BuildMovementAgents();
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
                var frames = new ImageSource[6];
                for (int frame = 0; frame < frames.Length; frame++)
                {
                    frames[frame] = await StorePreviewImageLoader.LoadFrameAsync(
                        path,
                        checked((uint)definition.FrameWidth),
                        checked((uint)definition.FrameHeight),
                        frame,
                        renderedWidth: 48,
                        renderedHeight: 48);
                }
                _characters[id] = frames;
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
        double leftX;
        double rightX;
        if (ProductKind == CommerceProductKind.Throwable)
        {
            leftX = 92;
            rightX = 400;
            ApplyCharacterFrame(LeftCharacter, LeftCharacterScale, leftId, frame: 0, facingLeft: false);
            ApplyCharacterFrame(RightCharacter, RightCharacterScale, "pixel_cat", frame: 0, facingLeft: true);
        }
        else
        {
            AdvanceMovement(elapsed);
            PixelMovementAgent leftAgent = _movementAgents[0];
            PixelMovementAgent rightAgent = _movementAgents[1];
            leftX = leftAgent.TrackPosition - 24;
            rightX = rightAgent.TrackPosition - 24;
            int leftFrame = CharacterFrame(elapsed, leftAgent.Velocity);
            int rightFrame = CharacterFrame(elapsed + 0.08, rightAgent.Velocity);
            ApplyCharacterFrame(
                LeftCharacter,
                LeftCharacterScale,
                leftId,
                leftFrame,
                leftAgent.Velocity < -0.1);
            ApplyCharacterFrame(
                RightCharacter,
                RightCharacterScale,
                "pixel_cat",
                rightFrame,
                rightAgent.Velocity < -0.1);
        }
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
        Canvas.SetLeft(
            LeftNameplate,
            Math.Clamp(leftX - 10, 4, StageWidth - LeftNameplate.Width - 4));
        Canvas.SetLeft(
            RightNameplate,
            Math.Clamp(rightX - 10, 4, StageWidth - RightNameplate.Width - 4));
    }

    private void BuildMovementAgents()
    {
        double lower = _movementGeometry.TrackLowerBound;
        double length = _movementGeometry.TrackUpperBound - lower;
        double leftFraction = ProductKind == CommerceProductKind.Bubble ? 0.28 : 0.22;
        double rightFraction = ProductKind == CommerceProductKind.Bubble ? 0.72 : 0.78;
        _movementAgents.Add(new PixelMovementAgent(
            new Guid("D5F0D9BB-FBDA-4B10-AEF9-A7E2A4CFBD25"),
            lower + (length * leftFraction),
            _movementGeometry.TrackUpperBound));
        _movementAgents.Add(new PixelMovementAgent(
            new Guid("26E5237A-69A1-4EA7-868E-822C831069B6"),
            lower + (length * rightFraction),
            _movementGeometry.TrackLowerBound));
    }

    private void AdvanceMovement(double elapsed)
    {
        double deltaTime = _lastSceneElapsed <= 0
            ? 1d / 30d
            : Math.Clamp(elapsed - _lastSceneElapsed, 0, 0.1);
        _lastSceneElapsed = elapsed;

        double lower = _movementGeometry.TrackLowerBound;
        double upper = _movementGeometry.TrackUpperBound;
        foreach (PixelMovementAgent agent in _movementAgents)
        {
            if (Math.Abs(agent.Target - agent.TrackPosition) > 2)
            {
                continue;
            }

            if (agent.TrackPosition <= lower + 2)
            {
                TurnFromWall(agent, towardUpper: true, lower, upper);
            }
            else if (agent.TrackPosition >= upper - 2)
            {
                TurnFromWall(agent, towardUpper: false, lower, upper);
            }
            else
            {
                agent.Target = RandomTarget(lower, upper);
                agent.IdleRemaining = 0.6 + (_random.NextDouble() * 1.4);
            }
        }

        PixelMovementSimulation.Step(
            _movementAgents,
            deltaTime,
            _movementGeometry,
            NoAvoidanceRects,
            NoStoppedIds,
            _movementScratch);

        foreach (PixelMovementAgent agent in _movementAgents)
        {
            if (agent.TrackPosition <= lower + 0.01 && agent.Velocity < 0)
            {
                TurnFromWall(agent, towardUpper: true, lower, upper);
            }
            else if (agent.TrackPosition >= upper - 0.01 && agent.Velocity > 0)
            {
                TurnFromWall(agent, towardUpper: false, lower, upper);
            }
        }
    }

    private double RandomTarget(double lower, double upper) =>
        lower + (_random.NextDouble() * (upper - lower));

    private void TurnFromWall(
        PixelMovementAgent agent,
        bool towardUpper,
        double lower,
        double upper)
    {
        double midpoint = lower + ((upper - lower) / 2d);
        agent.Target = towardUpper
            ? midpoint + (_random.NextDouble() * (upper - midpoint))
            : lower + (_random.NextDouble() * (midpoint - lower));
        agent.Velocity = towardUpper
            ? Math.Max(6, Math.Abs(agent.Velocity))
            : -Math.Max(6, Math.Abs(agent.Velocity));
        agent.IdleRemaining = 0;
    }

    private static int CharacterFrame(double elapsed, double velocity) =>
        Math.Abs(velocity) > 2
            ? 2 + ((int)(elapsed / WalkFrameSeconds) % 4)
            : (int)(elapsed / 0.6) % 2;

    private void ApplyCharacterFrame(
        Image image,
        ScaleTransform transform,
        string characterId,
        int frame,
        bool facingLeft)
    {
        IReadOnlyList<ImageSource> frames = _characters[characterId];
        image.Source = frames[Math.Clamp(frame, 0, frames.Count - 1)];
        transform.ScaleX = facingLeft ? -1 : 1;
    }

    private void UpdateBubble(double elapsed, double leftX, double rightX)
    {
        double phase = elapsed % 6;
        bool fromLeft = phase < 3;
        double local = phase % 3;
        bool typing = local < 1;
        BubbleText.Text = typing
            ? new string('.', 1 + ((int)(local * 3) % 3))
            : fromLeft ? "저메추좀 해줘" : "곱도리탕 어때?";
        double bubbleWidth = typing ? 54 : 142;
        double decorationLeadingOverflow = typing ? 0 : 6;
        double decorationTopOverflow = typing ? 0 : 8;
        BubblePreview.Width = bubbleWidth + decorationLeadingOverflow;
        BubblePreview.Height = 50 + decorationTopOverflow;
        BubbleBody.Width = bubbleWidth;
        Canvas.SetLeft(BubbleBody, decorationLeadingOverflow);
        Canvas.SetTop(BubbleBody, decorationTopOverflow);
        BubbleDecoration.Visibility = typing ? Visibility.Collapsed : Visibility.Visible;
        Canvas.SetLeft(BubbleDecoration, 0);
        Canvas.SetTop(BubbleDecoration, 0);
        Canvas.SetTop(BubbleTail, 41 + decorationTopOverflow);
        Canvas.SetLeft(
            BubbleTail,
            decorationLeadingOverflow + (fromLeft ? 18 : bubbleWidth - 32));
        double bodyLeft = fromLeft
            ? leftX - 4
            : rightX + 48 - bubbleWidth + 4;
        Canvas.SetLeft(
            BubblePreview,
            bodyLeft - decorationLeadingOverflow);
        Canvas.SetTop(BubblePreview, 132 - decorationTopOverflow);
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
