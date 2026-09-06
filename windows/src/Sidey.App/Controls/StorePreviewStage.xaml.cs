using System.Diagnostics;
using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.Text;
using Microsoft.Graphics.Canvas.UI;
using Microsoft.Graphics.Canvas.UI.Xaml;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Sidey.Core.Domain;
using Sidey.Platform.Windows;
using Windows.Foundation;
using Windows.UI;
using Windows.UI.ViewManagement;

namespace Sidey.App.Controls;

public sealed partial class StorePreviewStage : UserControl
{
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(1000d / 30d) };
    private readonly Stopwatch _clock = new();
    private readonly Dictionary<string, CanvasBitmap> _characters = new(StringComparer.Ordinal);
    private readonly Color _foregroundColor;
    private CanvasBitmap? _cosmetic;
    private CanvasBitmap? _decoration;
    private CanvasBitmap? _emitter;
    private double _manualThrowStarted = -10;
    private bool _loadFailed;

    public StorePreviewStage(CommerceProductKind kind, string catalogItemId, string characterId)
    {
        InitializeComponent();
        ProductKind = kind;
        CatalogItemId = catalogItemId;
        CharacterId = characterId;
        var uiSettings = new UISettings();
        _foregroundColor = uiSettings.GetColorValue(UIColorType.Foreground);
        _timer.Tick += (_, _) => StageCanvas.Invalidate();
        if (uiSettings.AnimationsEnabled)
        {
            _clock.Start();
            _timer.Start();
        }
    }

    public CommerceProductKind ProductKind { get; }
    public string CatalogItemId { get; }
    public string CharacterId { get; }

    private async void OnCreateResources(CanvasControl sender, CanvasCreateResourcesEventArgs args)
    {
        _ = args;
        try
        {
            string root = Path.Combine(SideyDeploymentPaths.DeploymentRoot(), "Assets");
            foreach (string id in new[] { "pixel_hamster", "pixel_cat", CharacterId }
                         .Distinct(StringComparer.Ordinal))
            {
                PixelCharacterDefinition definition = PixelCharacterCatalog.Get(id);
                string path = Path.Combine(
                    root,
                    definition.SpriteSheetResource.Replace('/', Path.DirectorySeparatorChar));
                _characters[id] = await CanvasBitmap.LoadAsync(sender, path);
            }
            if (ProductKind == CommerceProductKind.Bubble)
            {
                _decoration = await CanvasBitmap.LoadAsync(sender,
                    Path.Combine(root, "Bubbles", CatalogItemId, "decoration.png"));
            }
            else
            {
                string objectId = ProductKind == CommerceProductKind.Throwable
                    ? CatalogItemId
                    : SignatureObject(CharacterId);
                _cosmetic = await CanvasBitmap.LoadAsync(sender,
                    Path.Combine(root, "Throwables", objectId, "sprite.png"));
                if (objectId == "throwable_toy_cannon")
                {
                    _emitter = await CanvasBitmap.LoadAsync(sender,
                        Path.Combine(root, "Throwables", objectId, "emitter.png"));
                }
            }
            _loadFailed = false;
        }
        catch (Exception)
        {
            _loadFailed = true;
        }
        sender.Invalidate();
    }

    private void OnDraw(CanvasControl sender, CanvasDrawEventArgs args)
    {
        var drawing = args.DrawingSession;
        if (_loadFailed)
        {
            using var format = new CanvasTextFormat
            {
                FontFamily = "Segoe UI",
                FontSize = 14,
                HorizontalAlignment = CanvasHorizontalAlignment.Center,
                VerticalAlignment = CanvasVerticalAlignment.Center,
            };
            drawing.DrawText(
                Sidey.Core.Localization.I18n.Get("store.previewUnavailable"),
                new Rect(20, 20, 500, 240),
                _foregroundColor,
                format);
            return;
        }
        double elapsed = _clock.IsRunning ? _clock.Elapsed.TotalSeconds : 0;
        DrawFloor(drawing);
        string leftId = ProductKind == CommerceProductKind.Character ? CharacterId : "pixel_hamster";
        DrawCharacter(drawing, leftId, 92, 190, elapsed, faceLeft: false);
        DrawCharacter(drawing, "pixel_cat", 400, 190, elapsed + 0.4, faceLeft: true);

        if (ProductKind == CommerceProductKind.Bubble)
        {
            DrawBubbleScenario(drawing, elapsed);
        }
        else
        {
            double start = ProductKind == CommerceProductKind.Throwable
                ? Math.Floor(Math.Max(0, elapsed - 0.35)) + 0.35
                : _manualThrowStarted;
            DrawThrow(drawing, elapsed - start);
        }
    }

    private void DrawFloor(CanvasDrawingSession drawing)
    {
        drawing.DrawLine(28, 238, 512, 238, WithAlpha(_foregroundColor, 70), 1);
        for (int x = 36; x < 510; x += 24)
        {
            drawing.FillRectangle(x, 242, 12, 2, WithAlpha(_foregroundColor, 35));
        }
    }

    private static Color WithAlpha(Color color, byte alpha) =>
        Color.FromArgb(alpha, color.R, color.G, color.B);

    private void DrawCharacter(CanvasDrawingSession drawing, string id, double x, double y, double elapsed, bool faceLeft)
    {
        if (!_characters.TryGetValue(PixelCharacterCatalog.NormalizeId(id), out var sheet))
        {
            return;
        }
        PixelCharacterDefinition definition = PixelCharacterCatalog.Get(id);
        int frame = 2 + ((int)(elapsed * 7) % 4);
        var source = new Rect(frame * definition.FrameWidth, 0, definition.FrameWidth, definition.FrameHeight);
        var destination = new Rect(x, y, 48, 48);
        if (!faceLeft)
        {
            drawing.DrawImage(sheet, destination, source, 1, CanvasImageInterpolation.NearestNeighbor);
            return;
        }
        drawing.Transform = System.Numerics.Matrix3x2.CreateScale(-1, 1, new System.Numerics.Vector2((float)(x + 24), 0));
        drawing.DrawImage(sheet, destination, source, 1, CanvasImageInterpolation.NearestNeighbor);
        drawing.Transform = System.Numerics.Matrix3x2.Identity;
    }

    private void DrawBubbleScenario(CanvasDrawingSession drawing, double elapsed)
    {
        double phase = elapsed % 6;
        bool fromLeft = phase < 3;
        double local = phase % 3;
        string text = local < 1 ? new string('.', 1 + ((int)(local * 3) % 3))
            : fromLeft ? "저메추좀 해줘" : "곱도리탕 어때?";
        var theme = BubbleColors(CatalogItemId);
        float width = local < 1 ? 54 : 124;
        float x = fromLeft ? 72 : 344;
        drawing.FillRoundedRectangle(x, 128, width, 42, 10, 10, theme.Background);
        drawing.DrawRoundedRectangle(x + .5f, 128.5f, width - 1, 41, 10, 10,
            Color.FromArgb(50, 20, 23, 31), 1);
        using var format = new CanvasTextFormat
        {
            FontFamily = "Segoe UI",
            FontSize = local < 1 ? 16 : 13,
            HorizontalAlignment = CanvasHorizontalAlignment.Center,
            VerticalAlignment = CanvasVerticalAlignment.Center,
        };
        drawing.DrawText(text, new Rect(x + 8, 129, width - 16, 40), theme.Foreground, format);
        if (_decoration is not null)
        {
            drawing.DrawImage(_decoration, new Rect(x - 8, 122, 32, 32), new Rect(0, 0, 16, 16),
                1, CanvasImageInterpolation.NearestNeighbor);
        }
    }

    private void DrawThrow(CanvasDrawingSession drawing, double local)
    {
        if (local < 0 || local > 1.1)
        {
            return;
        }
        string objectId = ProductKind == CommerceProductKind.Throwable
            ? CatalogItemId
            : SignatureObject(CharacterId);
        CanvasBitmap? sheet = _cosmetic;
        if (sheet is null)
        {
            return;
        }
        if (objectId == "throwable_toy_cannon" && _emitter is not null && local < 0.4)
        {
            int emitterFrame = Math.Min(3, (int)(local / 0.1));
            drawing.DrawImage(_emitter, new Rect(92, 190, 48, 48), new Rect(emitterFrame * 24, 0, 24, 24),
                1, CanvasImageInterpolation.NearestNeighbor);
        }
        double progress = Math.Clamp((local - 0.2) / 0.65, 0, 1);
        int frame = progress >= 1 ? 8 + Math.Min(3, (int)((local - .85) / .06)) : (int)(local / .083) % 8;
        double x = 132 + (292 * progress);
        double y = 210 - (Math.Sin(progress * Math.PI) * 62);
        drawing.DrawImage(sheet, new Rect(x, y, 32, 32), new Rect(frame * 16, 0, 16, 16),
            1, CanvasImageInterpolation.NearestNeighbor);
    }

    private static (Color Background, Color Foreground) BubbleColors(string id) => id switch
    {
        "bubble_bunny_pink" => (Color.FromArgb(245, 0xF7, 0xA9, 0xB8), Color.FromArgb(255, 0x1C, 0x1F, 0x29)),
        "bubble_butter_chick" => (Color.FromArgb(245, 0xFF, 0xE3, 0x8A), Color.FromArgb(255, 0x1C, 0x1F, 0x29)),
        _ => (Color.FromArgb(245, 0x40, 0x3A, 0x78), Color.FromArgb(255, 0xFF, 0xF7, 0xE8)),
    };

    private static string SignatureObject(string characterId) => characterId switch
    {
        "pixel_guinea_pig" => "mini_paprika",
        "pixel_monkey" => "banana",
        "pixel_chinchilla" => "dust_bath_pouch",
        "pixel_starlight_upalupa" => "starlight_orb",
        _ => "patch_soft_ball",
    };

    private void OnTapped(object sender, TappedRoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (ProductKind == CommerceProductKind.Character)
        {
            _manualThrowStarted = _clock.Elapsed.TotalSeconds;
        }
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _timer.Stop();
        _clock.Stop();
        foreach (CanvasBitmap bitmap in _characters.Values)
        {
            bitmap.Dispose();
        }
        _characters.Clear();
        _cosmetic?.Dispose();
        _decoration?.Dispose();
        _emitter?.Dispose();
    }
}
