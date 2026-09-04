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
    IReadOnlyDictionary<Guid, PremultipliedVisual> MessageBubbles,
    IReadOnlyList<PremultipliedVisual> TypingFrames,
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
    private const float BubbleCornerRadiusDip = 9f;
    private const float BubbleBorderWidthDip = 1f;
    private const float TypingBubbleWidthDip = 42f;
    private const float TypingBubbleHeightDip = 30f;
    private const float DozeWidthDip = 42f;
    private const float DozeHeightDip = 28f;
    private const float DozeFontSizeDip = 14f;
    private const float DozeOutlineWidthDip = 2f;
    private const int DozeOutlineSampleCount = 12;
    private readonly CanvasDevice _device = CanvasDevice.GetSharedDevice();
    private readonly float _dpi;
    private readonly OverlayEdge _edge;
    private readonly float _bubbleMaximumWidthDip;
    private readonly Dictionary<Guid, CacheEntry> _entries = [];
    private readonly Dictionary<Guid, List<ActiveBubble>> _bubblesBySender = [];
    private readonly HashSet<Guid> _currentMemberIds = [];
    private readonly List<Guid> _removedMemberIds = [];
    private bool _disposed;

    public PixelTextVisualCache(
        uint dpi,
        OverlayEdge edge,
        float bubbleMaximumWidthDip = BubbleMaximumWidthDip)
    {
        _dpi = dpi;
        _edge = edge;
        _bubbleMaximumWidthDip = Math.Clamp(
            bubbleMaximumWidthDip,
            24f,
            BubbleMaximumWidthDip);
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
            if (!_bubblesBySender.TryGetValue(bubble.SenderId, out var senderBubbles))
            {
                senderBubbles = [];
                _bubblesBySender.Add(bubble.SenderId, senderBubbles);
            }
            senderBubbles.Add(bubble);
        }
        foreach (var senderBubbles in _bubblesBySender.Values)
        {
            senderBubbles.Sort(CompareBubbles);
            if (senderBubbles.Count > ActiveBubbleLedger.MaximumVisiblePerSender)
            {
                senderBubbles.RemoveRange(
                    0,
                    senderBubbles.Count - ActiveBubbleLedger.MaximumVisiblePerSender);
            }
        }
        foreach (var member in snapshot.Members)
        {
            _bubblesBySender.TryGetValue(member.Id, out var bubbles);
            BubbleVisualKey? olderBubble = bubbles is { Count: 2 }
                ? new BubbleVisualKey(bubbles[0].MessageId, bubbles[0].Body)
                : null;
            BubbleVisualKey? latestBubble = bubbles is { Count: > 0 }
                ? new BubbleVisualKey(bubbles[^1].MessageId, bubbles[^1].Body)
                : null;
            var key = new VisualKey(
                member.IsCurrentUser
                    ? I18n.Format("overlay.currentUser", member.Nickname)
                    : member.Nickname,
                member.Presence,
                olderBubble,
                latestBubble,
                member.IsTyping);
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

        var messageBubbles = new Dictionary<Guid, PremultipliedVisual>(
            ActiveBubbleLedger.MaximumVisiblePerSender);
        foreach (var bubble in BubbleKeys(key))
        {
            var (width, height) = MeasureBubble(bubble.Body);
            messageBubbles.Add(bubble.MessageId, PixelVisualOrientation.Apply(Rasterize(
                bubble.Body,
                width,
                height,
                background: Color.FromArgb(242, 255, 255, 255),
                foreground: Color.FromArgb(255, 27, 31, 40),
                cornerRadius: BubbleCornerRadiusDip,
                fontSize: BubbleFontSizeDip,
                horizontalPadding: BubbleHorizontalPaddingDip,
                verticalPadding: BubbleVerticalPaddingDip,
                border: Color.FromArgb(41, 20, 23, 31)), _edge));
        }
        IReadOnlyList<PremultipliedVisual> typingFrames = key.IsTyping
            ? [
                BuildTypingFrame("."),
                BuildTypingFrame(".."),
                BuildTypingFrame("..."),
            ]
            : [];

        var doze = key.Presence == PresenceState.Away
            ? PixelVisualOrientation.Apply(RasterizeDoze(), _edge)
            : null;
        return new PixelMemberVisuals(nameplate, messageBubbles, typingFrames, doze);
    }

    private PremultipliedVisual BuildTypingFrame(string body) =>
        PixelVisualOrientation.Apply(Rasterize(
            body,
            Math.Min(TypingBubbleWidthDip, _bubbleMaximumWidthDip),
            TypingBubbleHeightDip,
            background: Color.FromArgb(242, 255, 255, 255),
            foreground: Color.FromArgb(255, 84, 88, 100),
            cornerRadius: BubbleCornerRadiusDip,
            fontSize: 16f,
            border: Color.FromArgb(41, 20, 23, 31)), _edge);

    private static IEnumerable<BubbleVisualKey> BubbleKeys(VisualKey key)
    {
        if (key.OlderBubble is { } older)
        {
            yield return older;
        }
        if (key.LatestBubble is { } latest)
        {
            yield return latest;
        }
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
        var width = Math.Min(
            _bubbleMaximumWidthDip,
            Math.Max(
                BubbleMinimumWidthDip,
                (float)Math.Ceiling(naturalBounds.Width) + (BubbleHorizontalPaddingDip * 2f)));

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
        var height = Math.Max(
            28f,
            (float)Math.Ceiling(wrappedBounds.Height) + (BubbleVerticalPaddingDip * 2f));
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
        float verticalPadding = 1f,
        Color? border = null)
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
            if (border is { } borderColor)
            {
                var inset = BubbleBorderWidthDip / 2f;
                drawing.DrawRoundedRectangle(
                    inset,
                    inset,
                    widthDip - BubbleBorderWidthDip,
                    heightDip - BubbleBorderWidthDip,
                    cornerRadius,
                    cornerRadius,
                    borderColor,
                    BubbleBorderWidthDip);
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
        foreach (var messageBubble in visuals.MessageBubbles.Values)
        {
            Array.Clear(messageBubble.Pixels);
        }
        foreach (var typingBubble in visuals.TypingFrames)
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
        BubbleVisualKey? OlderBubble,
        BubbleVisualKey? LatestBubble,
        bool IsTyping);

    private readonly record struct BubbleVisualKey(Guid MessageId, string Body);

    private static int CompareBubbles(ActiveBubble left, ActiveBubble right)
    {
        var dateComparison = left.ExpiresAt.CompareTo(right.ExpiresAt);
        return dateComparison != 0
            ? dateComparison
            : StringComparer.Ordinal.Compare(
                left.MessageId.ToString("D"),
                right.MessageId.ToString("D"));
    }

    private sealed record CacheEntry(VisualKey Key, PixelMemberVisuals Visuals);
}
