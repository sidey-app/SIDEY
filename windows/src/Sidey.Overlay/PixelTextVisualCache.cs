using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.Text;
using Sidey.Core.Domain;
using Windows.Foundation;
using Windows.Graphics.DirectX;
using Windows.UI;

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
    private const float BubbleMaximumWidthDip = 220f;
    private const float BubbleMinimumWidthDip = 60f;
    private readonly CanvasDevice _device = CanvasDevice.GetSharedDevice();
    private readonly float _dpi;
    private readonly Dictionary<Guid, CacheEntry> _entries = [];
    private bool _disposed;

    public PixelTextVisualCache(uint dpi)
    {
        _dpi = dpi;
    }

    public void Update(WorldSnapshot snapshot)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var members = snapshot.Members.Select(member => member.Id).ToHashSet();
        foreach (var removed in _entries.Keys.Where(id => !members.Contains(id)).ToArray())
        {
            Clear(_entries[removed].Visuals);
            _entries.Remove(removed);
        }

        var bubbles = snapshot.Bubbles.ToDictionary(bubble => bubble.SenderId);
        foreach (var member in snapshot.Members)
        {
            bubbles.TryGetValue(member.Id, out var bubble);
            var key = new VisualKey(
                member.IsCurrentUser ? $"{member.Nickname} · 나" : member.Nickname,
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
        var nameplateWidth = Math.Clamp(30f + (key.Name.Length * 8f), 58f, 150f);
        var nameplate = Rasterize(
            key.Name,
            nameplateWidth,
            NameplateHeightDip,
            background: Color.FromArgb(158, 5, 6, 9),
            foreground: Color.FromArgb(255, 255, 255, 255),
            cornerRadius: 6f,
            fontSize: 11f,
            status: StatusColor(key.Presence));

        PremultipliedVisual? messageBubble = null;
        if (key.BubbleBody is { } body)
        {
            var lines = Math.Clamp(body.Count(character => character == '\n') + 1, 1, 3);
            var width = Math.Clamp(
                28f + (body.Split('\n').Max(line => line.Length) * 8f),
                BubbleMinimumWidthDip,
                BubbleMaximumWidthDip);
            var height = Math.Clamp(28f + ((lines - 1) * 17f), 28f, 66f);
            messageBubble = Rasterize(
                body,
                width,
                height,
                background: Color.FromArgb(242, 255, 255, 255),
                foreground: Color.FromArgb(255, 27, 31, 40),
                cornerRadius: 10f,
                fontSize: 12f);
        }
        var typingBubble = key.IsTyping
            ? Rasterize(
                "•••",
                48f,
                28f,
                background: Color.FromArgb(230, 255, 255, 255),
                foreground: Color.FromArgb(255, 84, 88, 100),
                cornerRadius: 10f,
                fontSize: 13f)
            : null;

        var doze = key.Presence == PresenceState.Away
            ? Rasterize(
                "Zzz",
                38f,
                22f,
                background: Color.FromArgb(0, 0, 0, 0),
                foreground: Color.FromArgb(235, 255, 255, 255),
                cornerRadius: 0f,
                fontSize: 12f)
            : null;
        return new PixelMemberVisuals(nameplate, messageBubble, typingBubble, doze);
    }

    private PremultipliedVisual Rasterize(
        string text,
        float widthDip,
        float heightDip,
        Color background,
        Color foreground,
        float cornerRadius,
        float fontSize,
        Color? status = null)
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
            if (status is { } statusColor)
            {
                drawing.FillCircle(8f, heightDip / 2f, 3f, statusColor);
            }
            drawing.DrawText(
                text,
                new Rect(
                    status is null ? 4f : 14f,
                    1f,
                    widthDip - (status is null ? 8f : 18f),
                    heightDip - 2f),
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
        PresenceState.Online or PresenceState.Typing => Color.FromArgb(255, 74, 222, 128),
        PresenceState.Away => Color.FromArgb(255, 250, 190, 70),
        PresenceState.Reconnecting => Color.FromArgb(255, 255, 142, 72),
        _ => Color.FromArgb(255, 145, 151, 164),
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
