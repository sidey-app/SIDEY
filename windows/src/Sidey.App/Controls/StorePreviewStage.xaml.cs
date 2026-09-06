using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Sidey.Core.Overlay;
using Sidey.Platform.Windows;
using Windows.Foundation;
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
    private const double ThrowActionSeconds = 0.4;
    private const double ThrowReleaseSeconds = 0.2;
    private const double ThrowFlightSeconds = 0.55;
    private const double HitActionSeconds = 0.44;
    private const double ImpactSeconds = 0.24;
    private const double ThrowCycleSeconds = 1.0;
    private const double AmbientSparkleCycleSeconds = 1.2;
    private const double AmbientSparkleDurationSeconds = 1.05;
    private static readonly IReadOnlyList<RectD> NoAvoidanceRects = Array.Empty<RectD>();
    private static readonly IReadOnlySet<Guid> NoStoppedIds = new HashSet<Guid>();
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(1000d / 30d) };
    private readonly Stopwatch _clock = new();
    private readonly Dictionary<string, IReadOnlyList<ImageSource>> _characters = new(StringComparer.Ordinal);
    private readonly Dictionary<string, IReadOnlyList<ImageSource>> _actions = new(StringComparer.Ordinal);
    private readonly EdgeTrackGeometry _movementGeometry = new(
        new RectD(0, 0, StageWidth, 280),
        OverlayEdge.Bottom,
        tangentExtent: RenderedCharacterSize + (PreviewWallInset * 2));
    private readonly List<PixelMovementAgent> _movementAgents = [];
    private readonly PixelMovementScratch _movementScratch = new();
    private readonly Random _random = new(0x51DE59);
    private readonly List<Microsoft.UI.Xaml.Shapes.Polygon> _sparkles = [];
    private IReadOnlyList<ImageSource> _projectileFrames = Array.Empty<ImageSource>();
    private IReadOnlyList<ImageSource> _emitterFrames = Array.Empty<ImageSource>();
    private double _manualThrowStarted = -10;
    private double _lastSceneElapsed;
    private bool _resourcesLoaded;
    private bool _loading;
    private bool _isLoaded;
    private bool _leftFacingLeft;
    private bool _rightFacingLeft;

    public StorePreviewStage(CommerceProductKind kind, string catalogItemId, string characterId)
    {
        InitializeComponent();
        ProductKind = kind;
        CatalogItemId = catalogItemId;
        CharacterId = PixelCharacterCatalog.NormalizeId(characterId);
        _timer.Tick += OnTimerTick;
        BuildPlatform();
        BuildSparkles();
        BuildMovementAgents();
    }

    public CommerceProductKind ProductKind { get; }
    public string CatalogItemId { get; }
    public string CharacterId { get; }

    private async void OnLoaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _isLoaded = true;
        await InitializeAsync();

        if (_isLoaded)
        {
            StartAnimation();
        }
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

                string actionPath = Path.Combine(root, "Characters", id, "throw_hit.png");
                var actionFrames = new ImageSource[8];
                for (int frame = 0; frame < actionFrames.Length; frame++)
                {
                    actionFrames[frame] = await StorePreviewImageLoader.LoadFrameAsync(
                        actionPath,
                        frameWidth: 24,
                        frameHeight: 24,
                        frame,
                        renderedWidth: 48,
                        renderedHeight: 48);
                }
                _actions[id] = actionFrames;
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
                var projectileFrames = new ImageSource[12];
                for (int frame = 0; frame < projectileFrames.Length; frame++)
                {
                    projectileFrames[frame] = await StorePreviewImageLoader.LoadFrameAsync(
                        objectPath,
                        frameWidth: 16,
                        frameHeight: 16,
                        frame,
                        renderedWidth: frame < 8 ? 32u : 48u,
                        renderedHeight: frame < 8 ? 32u : 48u);
                }
                _projectileFrames = projectileFrames;

                if (objectId == "throwable_toy_cannon")
                {
                    string emitterPath = Path.Combine(root, "Throwables", objectId, "emitter.png");
                    var emitterFrames = new ImageSource[4];
                    for (int frame = 0; frame < emitterFrames.Length; frame++)
                    {
                        emitterFrames[frame] = await StorePreviewImageLoader.LoadFrameAsync(
                            emitterPath,
                            frameWidth: 24,
                            frameHeight: 24,
                            frame,
                            renderedWidth: 48,
                            renderedHeight: 48);
                    }
                    _emitterFrames = emitterFrames;
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
            ApplyCharacterFrame(RightCharacter, RightCharacterScale, "pixel_cat", frame: 0, facingLeft: false);
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
            double manualThrowElapsed = elapsed - _manualThrowStarted;
            bool leftActionActive = manualThrowElapsed is >= 0 and < ThrowActionSeconds;
            double impactStarted = ThrowReleaseSeconds + ThrowFlightSeconds;
            bool rightActionActive = manualThrowElapsed >= impactStarted
                && manualThrowElapsed < impactStarted + HitActionSeconds;
            if (!leftActionActive)
            {
                UpdateFacing(leftAgent, leftId, ref _leftFacingLeft);
            }
            if (!rightActionActive)
            {
                UpdateFacing(rightAgent, "pixel_cat", ref _rightFacingLeft);
            }
            ApplyCharacterFrame(
                LeftCharacter,
                LeftCharacterScale,
                leftId,
                leftFrame,
                _leftFacingLeft);
            ApplyCharacterFrame(
                RightCharacter,
                RightCharacterScale,
                "pixel_cat",
                rightFrame,
                _rightFacingLeft);
        }
        PositionCharacters(leftX, rightX);
        UpdateSparkles(elapsed, leftX, leftId);

        if (ProductKind == CommerceProductKind.Bubble)
        {
            UpdateBubble(elapsed, leftX, rightX);
            ProjectileImage.Visibility = Visibility.Collapsed;
            EmitterImage.Visibility = Visibility.Collapsed;
            ImpactImage.Visibility = Visibility.Collapsed;
            return;
        }

        BubblePreview.Visibility = Visibility.Collapsed;
        if (ProductKind == CommerceProductKind.Throwable)
        {
            double sequenceTime = Math.Max(0, elapsed - 0.35);
            int sequenceIndex = (int)Math.Floor(sequenceTime / ThrowCycleSeconds);
            UpdateThrow(sequenceTime % ThrowCycleSeconds, leftX, rightX, sequenceIndex % 2 == 0);
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

    private static void UpdateFacing(
        PixelMovementAgent agent,
        string characterId,
        ref bool facingLeft)
    {
        if (!PixelCharacterCatalog.Get(characterId).MirrorsToMovementDirection)
        {
            facingLeft = false;
            return;
        }

        double targetDelta = agent.Target - agent.TrackPosition;
        if (Math.Abs(targetDelta) > 2d)
        {
            facingLeft = targetDelta < 0d;
        }
    }

    private void ApplyCharacterFrame(
        Image image,
        ScaleTransform transform,
        string characterId,
        int frame,
        bool facingLeft)
    {
        IReadOnlyList<ImageSource> frames = _characters[characterId];
        image.Source = frames[Math.Clamp(frame, 0, frames.Count - 1)];
        transform.ScaleX = PixelCharacterCatalog.Get(characterId).MirrorsToMovementDirection
            && facingLeft
                ? -1
                : 1;
    }

    private void ApplyActionFrame(
        Image image,
        ScaleTransform transform,
        string characterId,
        int frame,
        bool facingLeft)
    {
        IReadOnlyList<ImageSource> frames = _actions[characterId];
        image.Source = frames[Math.Clamp(frame, 0, frames.Count - 1)];
        transform.ScaleX = PixelCharacterCatalog.Get(characterId).MirrorsToMovementDirection
            && facingLeft
                ? -1
                : 1;
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
        ImpactImage.Visibility = Visibility.Collapsed;
        double sequenceEnd = ProductKind == CommerceProductKind.Throwable
            ? ThrowCycleSeconds
            : ThrowReleaseSeconds + ThrowFlightSeconds + HitActionSeconds;
        if (local < 0 || local >= sequenceEnd || _projectileFrames.Count < 12)
        {
            ProjectileImage.Visibility = Visibility.Collapsed;
            EmitterImage.Visibility = Visibility.Collapsed;
            return;
        }

        string leftId = ProductKind == CommerceProductKind.Character
            ? CharacterId
            : PixelCharacterCatalog.FallbackId;
        Image actor = leftToRight ? LeftCharacter : RightCharacter;
        Image target = leftToRight ? RightCharacter : LeftCharacter;
        ScaleTransform actorTransform = leftToRight ? LeftCharacterScale : RightCharacterScale;
        ScaleTransform targetTransform = leftToRight ? RightCharacterScale : LeftCharacterScale;
        string actorId = leftToRight ? leftId : "pixel_cat";
        string targetId = leftToRight ? "pixel_cat" : leftId;
        bool actorFacingLeft = leftToRight ? _leftFacingLeft : _rightFacingLeft;
        bool targetFacingLeft = leftToRight ? _rightFacingLeft : _leftFacingLeft;

        if (local < ThrowActionSeconds)
        {
            int actionFrame = Math.Min(3, (int)(local / (ThrowActionSeconds / 4d)));
            ApplyActionFrame(actor, actorTransform, actorId, actionFrame, actorFacingLeft);
        }

        double impactStarted = ThrowReleaseSeconds + ThrowFlightSeconds;
        if (local >= impactStarted && local < impactStarted + HitActionSeconds)
        {
            int hitFrame = 4 + Math.Min(
                3,
                (int)((local - impactStarted) / (HitActionSeconds / 4d)));
            ApplyActionFrame(target, targetTransform, targetId, hitFrame, targetFacingLeft);
        }

        if (local >= ThrowReleaseSeconds && local < impactStarted)
        {
            double progress = (local - ThrowReleaseSeconds) / ThrowFlightSeconds;
            double startCenterX = leftToRight ? leftX + 24 : rightX + 24;
            double endCenterX = leftToRight ? rightX + 24 : leftX + 24;
            double centerX = startCenterX + ((endCenterX - startCenterX) * progress);
            double centerY = PlatformTop - 10 - (Math.Sin(progress * Math.PI) * 72);
            int projectileFrame = (int)((local - ThrowReleaseSeconds) / 0.083) % 8;
            ProjectileImage.Source = _projectileFrames[projectileFrame];
            ProjectileScale.ScaleX = 1;
            Canvas.SetLeft(ProjectileImage, centerX - 16);
            Canvas.SetTop(ProjectileImage, centerY - 16);
            ProjectileImage.Visibility = Visibility.Visible;
        }
        else
        {
            ProjectileImage.Visibility = Visibility.Collapsed;
        }

        if (local >= impactStarted && local < impactStarted + ImpactSeconds)
        {
            int impactFrame = 8 + Math.Min(
                3,
                (int)((local - impactStarted) / (ImpactSeconds / 4d)));
            ImpactImage.Source = _projectileFrames[impactFrame];
            Canvas.SetLeft(ImpactImage, (leftToRight ? rightX : leftX));
            Canvas.SetTop(ImpactImage, PlatformTop - 34);
            ImpactImage.Visibility = Visibility.Visible;
        }

        if (_emitterFrames.Count == 4 && local < ThrowActionSeconds)
        {
            int emitterFrame = Math.Min(3, (int)(local / (ThrowActionSeconds / 4d)));
            EmitterImage.Source = _emitterFrames[emitterFrame];
            EmitterScale.ScaleX = leftToRight ? 1 : -1;
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

    private void BuildSparkles()
    {
        Color[] colors =
        [
            Color.FromArgb(255, 120, 194, 173),
            Color.FromArgb(255, 168, 135, 214),
            Color.FromArgb(255, 245, 186, 56),
        ];
        for (int index = 0; index < 6; index++)
        {
            double radius = 3 + ((index % 3) * 0.5);
            var star = new Microsoft.UI.Xaml.Shapes.Polygon
            {
                Fill = new SolidColorBrush(colors[index % colors.Length]),
                Points = new PointCollection
                {
                    new Point(radius, 0),
                    new Point(radius + 1, radius - 1),
                    new Point(radius * 2, radius),
                    new Point(radius + 1, radius + 1),
                    new Point(radius, radius * 2),
                    new Point(radius - 1, radius + 1),
                    new Point(0, radius),
                    new Point(radius - 1, radius - 1),
                },
                Opacity = 0,
            };
            _sparkles.Add(star);
            SparkleCanvas.Children.Add(star);
        }
    }

    private void UpdateSparkles(double elapsed, double leftX, string leftId)
    {
        bool active = PixelCharacterCatalog.Get(leftId).VisualEffect
            == PixelCharacterVisualEffect.StarlightSparkles;
        SparkleCanvas.Visibility = active ? Visibility.Visible : Visibility.Collapsed;
        if (!active)
        {
            return;
        }

        double phase = elapsed % AmbientSparkleCycleSeconds;
        for (int index = 0; index < _sparkles.Count; index++)
        {
            double local = phase - (index * 0.045);
            var star = _sparkles[index];
            if (local < 0 || local > AmbientSparkleDurationSeconds)
            {
                star.Opacity = 0;
                continue;
            }

            double progress = local / AmbientSparkleDurationSeconds;
            double horizontal = -25 + (50 * Unit((index + 1) * 7919));
            double vertical = 5 + (32 * Unit(((index + 1) * 1543) ^ 0x51A7));
            double rise = 4 * progress;
            double radius = 3 + ((index % 3) * 0.5);
            Canvas.SetLeft(star, leftX + 24 + horizontal - radius);
            Canvas.SetTop(star, PlatformTop - vertical - rise - radius);
            star.Opacity = Math.Sin(Math.PI * progress) * 0.96;
        }
    }

    private static double Unit(int value)
    {
        uint mixed = (uint)value;
        mixed ^= mixed >> 16;
        mixed *= 0x7FEB352D;
        mixed ^= mixed >> 15;
        mixed *= 0x846CA68B;
        mixed ^= mixed >> 16;
        return mixed / (double)uint.MaxValue;
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
        _isLoaded = false;
    }
}
