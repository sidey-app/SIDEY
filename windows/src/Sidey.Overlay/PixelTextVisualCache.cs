using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.Text;
using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Windows.Foundation;
using Windows.Graphics.DirectX;
using Windows.UI;
using Windows.UI.Text;

namespace Sidey.Overlay;

internal sealed record PremultipliedVisual(byte[] Pixels, int Width, int Height);

internal sealed record PixelMemberVisuals(
    PremultipliedVisual Nameplate,
    PremultipliedVisual? MessageBubble,
    PremultipliedVisual? TypingBubble,
    PremultipliedVisual? Doze);

/// <summary>
/// Rasterizes text only when an immutable world snapshot changes. The 30 FPS
/// render loop composites cached premultiplied BGRA buffers and never creates
/// text layouts, bitmaps, or GPU surfaces per tick.
/// </summary>
internal sealed class PixelTextVisualCache : IDisposable
{
    private const float NameplateHeightDip = 20f;
    private const float NameplateMinimumWidthDip = 20f;
    private const float NameplateMaximumWidthDip = 190f;
    private const float NameplateHorizontalPaddingDip = 4f;
    private const float NameplateStatusSpacingDip = 5f;
    private const float NameplateStatusRadiusDip = 3f;
    private const float BubbleMaximumWidthDip = 220f;
    private const float BubbleMinimumWidthDip = 28f;
    private const float BubbleHorizontalPaddingDip = 8f;
    private const float BubbleVerticalPaddingDip = 7f;
    private const float BubbleFontSizeDip = 10.5f;
    private const float DozeWidthDip = 42f;
    private const float DozeHeightDip = 28f;
    private const float DozeFontSizeDip = 14f;
    private const float DozeOutlineWidthDip = 2f;
    private const int DozeOutlineSampleCount = 12;
    private readonly CanvasDevice _device = CanvasDevice.GetSharedDevice();
    private readonly float _dpi;
    private readonly OverlayEdge _edge;
    private readonly Dictionary<Guid, CacheEntry> _entries = [];
    private readonly Dictionary<Guid, ActiveBubble> _bubblesBySender = [];
    private readonly HashSet<Guid> _currentMemberIds = [];
    private readonly List<Guid> _removedMemberIds = [];
    private bool _disposed;

    public PixelTextVisualCache(uint dpi, OverlayEdge edge)
    {
        _dpi = dpi;
        _edge = edge;
    }

    public void Update(WorldSnapshot snapshot)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        _currentMemberIds.Clear();
        foreach (var member in snapshot.Members)
        {
            _currentMemberIds.Add(member.Id);
        }

        _removedMemberIds.Clear();
        foreach (var memberId in _entries.Keys)
        {
            if (!_currentMemberIds.Contains(memberId))
            {
                _removedMemberIds.Add(memberId);
            }
        }
        foreach (var removed in _removedMemberIds)
        {
            Clear(_entries[removed].Visuals);
            _entries.Remove(removed);
        }

        _bubblesBySender.Clear();
        foreach (var bubble in snapshot.Bubbles)
        {
            _bubblesBySender[bubble.SenderId] = bubble;
        }
        foreach (var member in snapshot.Members)
        {
            _bubblesBySender.TryGetValue(member.Id, out var bubble);
            var key = new VisualKey(
                member.IsCurrentUser
                    ? I18n.Format("overlay.currentUser", member.Nickname)
                    : member.Nickname,
                member.Presence,
                bubble?.MessageId,
                bubble?.Body,
                bubble is null && member.IsTyping);
            if (_entries.TryGetValue(member.Id, out var existing) && existing.Key == key)
            {
                continue;
            }

            if (existing is not null)
            {
                Clear(existing.Visuals);
            }
            _entries[member.Id] = new CacheEntry(key, Build(key));
        }
    }

    public PixelMemberVisuals Get(Guid memberId)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        return _entries.TryGetValue(memberId, out var entry)
            ? entry.Visuals
            : throw new KeyNotFoundException($"No cached text visuals for member {memberId:D}.");
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        foreach (var entry in _entries.Values)
        {
            Clear(entry.Visuals);
        }
        _entries.Clear();
    }

    private PixelMemberVisuals Build(VisualKey key)
    {
        var nameplate = PixelVisualOrientation.Apply(RasterizeNameplate(
            key.Name,
            StatusColor(key.Presence)), _edge);

        PremultipliedVisual? messageBubble = null;
        if (key.BubbleBody is { } body)
        {
            var (width, height) = MeasureBubble(body);
            messageBubble = PixelVisualOrientation.Apply(Rasterize(
                body,
                width,
                height,
                background: Color.FromArgb(242, 255, 255, 255),
                foreground: Color.FromArgb(255, 27, 31, 40),
                cornerRadius: 10f,
                fontSize: BubbleFontSizeDip,
                horizontalPadding: BubbleHorizontalPaddingDip,
                verticalPadding: BubbleVerticalPaddingDip), _edge);
        }
        var typingBubble = key.IsTyping
            ? PixelVisualOrientation.Apply(Rasterize(
                "•••",
                48f,
                28f,
                background: Color.FromArgb(230, 255, 255, 255),
                foreground: Color.FromArgb(255, 84, 88, 100),
                cornerRadius: 10f,
                fontSize: 13f), _edge)
            : null;

        var doze = key.Presence == PresenceState.Away
            ? PixelVisualOrientation.Apply(RasterizeDoze(), _edge)
            : null;
        return new PixelMemberVisuals(nameplate, messageBubble, typingBubble, doze);
    }

    private PremultipliedVisual RasterizeDoze()
    {
        using var target = new CanvasRenderTarget(
            _device,
            DozeWidthDip,
            DozeHeightDip,
            _dpi,
            DirectXPixelFormat.B8G8R8A8UIntNormalized,
            CanvasAlphaMode.Premultiplied);
        using (var drawing = target.CreateDrawingSession())
        using (var format = new CanvasTextFormat
        {
            FontFamily = "Segoe UI",
            FontSize = DozeFontSizeDip,
            FontWeight = Microsoft.UI.Text.FontWeights.Bold,
            HorizontalAlignment = CanvasHorizontalAlignment.Center,
            VerticalAlignment = CanvasVerticalAlignment.Center,
            WordWrapping = CanvasWordWrapping.NoWrap,
        })
        {
            drawing.Clear(Color.FromArgb(0, 0, 0, 0));
            var textBounds = new Rect(
                DozeOutlineWidthDip,
                DozeOutlineWidthDip,
                DozeWidthDip - (DozeOutlineWidthDip * 2f),
                DozeHeightDip - (DozeOutlineWidthDip * 2f));
            Color outline = Color.FromArgb(235, 20, 18, 15);
            for (var index = 0; index < DozeOutlineSampleCount; index++)
            {
                double angle = index * Math.PI * 2d / DozeOutlineSampleCount;
                drawing.DrawText(
                    "Zzz",
                    new Rect(
                        textBounds.X + (Math.Cos(angle) * DozeOutlineWidthDip),
                        textBounds.Y + (Math.Sin(angle) * DozeOutlineWidthDip),
                        textBounds.Width,
                        textBounds.Height),
                    outline,
                    format);
            }

            drawing.DrawText(
                "Zzz",
                textBounds,
                Color.FromArgb(255, 255, 149, 0),
                format);
        }

        var size = target.SizeInPixels;
        return new PremultipliedVisual(
            target.GetPixelBytes(),
            checked((int)size.Width),
            checked((int)size.Height));
    }

    private (float Width, float Height) MeasureBubble(string body)
    {
        using var naturalFormat = new CanvasTextFormat
        {
            FontFamily = "Segoe UI",
            FontSize = BubbleFontSizeDip,
            HorizontalAlignment = CanvasHorizontalAlignment.Center,
            VerticalAlignment = CanvasVerticalAlignment.Center,
            WordWrapping = CanvasWordWrapping.NoWrap,
        };
        using var naturalLayout = new CanvasTextLayout(
            _device,
            body,
            naturalFormat,
            10_000f,
            1_000f);
        var naturalBounds = naturalLayout.LayoutBoundsIncludingTrailingWhitespace;
        var width = Math.Clamp(
            (float)Math.Ceiling(naturalBounds.Width) + (BubbleHorizontalPaddingDip * 2f),
            BubbleMinimumWidthDip,
            BubbleMaximumWidthDip);

        using var wrappedFormat = new CanvasTextFormat
        {
            FontFamily = "Segoe UI",
            FontSize = BubbleFontSizeDip,
            HorizontalAlignment = CanvasHorizontalAlignment.Center,
            VerticalAlignment = CanvasVerticalAlignment.Center,
            WordWrapping = CanvasWordWrapping.Wrap,
        };
        using var wrappedLayout = new CanvasTextLayout(
            _device,
            body,
            wrappedFormat,
            width - (BubbleHorizontalPaddingDip * 2f),
            1_000f);
        var wrappedBounds = wrappedLayout.LayoutBoundsIncludingTrailingWhitespace;
        var height = Math.Clamp(
            (float)Math.Ceiling(wrappedBounds.Height) + (BubbleVerticalPaddingDip * 2f),
            28f,
            66f);
        return (width, height);
    }

    private PremultipliedVisual RasterizeNameplate(
        string text,
        Color status)
    {
        using var format = new CanvasTextFormat
        {
            FontFamily = "Segoe UI",
            FontSize = 11f,
            HorizontalAlignment = CanvasHorizontalAlignment.Center,
            VerticalAlignment = CanvasVerticalAlignment.Center,
            WordWrapping = CanvasWordWrapping.NoWrap,
        };
        using var layout = new CanvasTextLayout(
            _device,
            text,
            format,
            NameplateMaximumWidthDip,
            NameplateHeightDip);
        var measuredTextWidth = (float)Math.Ceiling(layout.DrawBounds.Width);
        var boxWidthDip = Math.Clamp(
            measuredTextWidth + (NameplateHorizontalPaddingDip * 2f),
            NameplateMinimumWidthDip,
            NameplateMaximumWidthDip);
        var boxLeftDip = (NameplateStatusRadiusDip * 2f) + NameplateStatusSpacingDip;
        var widthDip = boxLeftDip + boxWidthDip;
        using var target = new CanvasRenderTarget(
            _device,
            widthDip,
            NameplateHeightDip,
            _dpi,
            DirectXPixelFormat.B8G8R8A8UIntNormalized,
            CanvasAlphaMode.Premultiplied);
        using (var drawing = target.CreateDrawingSession())
        {
            drawing.Clear(Color.FromArgb(0, 0, 0, 0));
            drawing.FillRoundedRectangle(
                boxLeftDip,
                0,
                boxWidthDip,
                NameplateHeightDip,
                6f,
                6f,
                Color.FromArgb(158, 5, 6, 9));
            drawing.FillCircle(
                NameplateStatusRadiusDip,
                NameplateHeightDip / 2f,
                NameplateStatusRadiusDip,
                status);
            drawing.DrawText(
                text,
                new Rect(
                    boxLeftDip + NameplateHorizontalPaddingDip,
                    1f,
                    boxWidthDip - (NameplateHorizontalPaddingDip * 2f),
                    NameplateHeightDip - 2f),
                Color.FromArgb(255, 255, 255, 255),
                format);
        }

        var size = target.SizeInPixels;
        return new PremultipliedVisual(
            target.GetPixelBytes(),
            checked((int)size.Width),
            checked((int)size.Height));
    }

    private PremultipliedVisual Rasterize(
        string text,
        float widthDip,
        float heightDip,
        Color background,
        Color foreground,
        float cornerRadius,
        float fontSize,
        float horizontalPadding = 4f,
        float verticalPadding = 1f)
    {
        using var target = new CanvasRenderTarget(
            _device,
            widthDip,
            heightDip,
            _dpi,
            DirectXPixelFormat.B8G8R8A8UIntNormalized,
            CanvasAlphaMode.Premultiplied);
        using (var drawing = target.CreateDrawingSession())
        using (var format = new CanvasTextFormat
        {
            FontFamily = "Segoe UI",
            FontSize = fontSize,
            HorizontalAlignment = CanvasHorizontalAlignment.Center,
            VerticalAlignment = CanvasVerticalAlignment.Center,
            WordWrapping = CanvasWordWrapping.Wrap,
        })
        {
            drawing.Clear(Color.FromArgb(0, 0, 0, 0));
            if (background.A > 0)
            {
                drawing.FillRoundedRectangle(
                    0,
                    0,
                    widthDip,
                    heightDip,
                    cornerRadius,
                    cornerRadius,
                    background);
            }
            drawing.DrawText(
                text,
                new Rect(
                    horizontalPadding,
                    verticalPadding,
                    widthDip - (horizontalPadding * 2f),
                    heightDip - (verticalPadding * 2f)),
                foreground,
                format);
        }

        var size = target.SizeInPixels;
        return new PremultipliedVisual(
            target.GetPixelBytes(),
            checked((int)size.Width),
            checked((int)size.Height));
    }

    private static Color StatusColor(PresenceState presence) => presence switch
    {
        PresenceState.Online or PresenceState.Typing => Color.FromArgb(255, 52, 199, 89),
        PresenceState.Away => Color.FromArgb(255, 255, 149, 0),
        PresenceState.Offline => Color.FromArgb(255, 255, 59, 48),
        PresenceState.Reconnecting => Color.FromArgb(255, 142, 142, 147),
        _ => throw new ArgumentOutOfRangeException(nameof(presence)),
    };

    private static void Clear(PixelMemberVisuals visuals)
    {
        Array.Clear(visuals.Nameplate.Pixels);
        if (visuals.MessageBubble is { } messageBubble)
        {
            Array.Clear(messageBubble.Pixels);
        }
        if (visuals.TypingBubble is { } typingBubble)
        {
            Array.Clear(typingBubble.Pixels);
        }
        if (visuals.Doze is { } doze)
        {
            Array.Clear(doze.Pixels);
        }
    }

    private sealed record VisualKey(
        string Name,
        PresenceState Presence,
        Guid? BubbleId,
        string? BubbleBody,
        bool IsTyping);

    private sealed record CacheEntry(VisualKey Key, PixelMemberVisuals Visuals);
}
