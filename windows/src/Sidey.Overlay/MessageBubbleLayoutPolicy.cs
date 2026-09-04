using Sidey.Core.Domain;
using Sidey.Core.Overlay;

namespace Sidey.Overlay;

internal readonly record struct MessageBubbleTail(
    PointD BaseStart,
    PointD Tip,
    PointD BaseEnd);

internal static class MessageBubbleLayoutPolicy
{
    internal const double TangentMarginDip = 4d;
    internal const double BodySpacingDip = 6d;
    internal const double TailHeightDip = 8d;
    internal const double TailHalfBaseDip = 6d;
    internal const double TailBaseInsetDip = 10d;
    internal const double TailBodyOverlapDip = 2d;
    internal const double CharacterGapDip = 4d;
    internal const double TypingFrameIntervalSeconds = 0.35d;

    internal static double ClampedTangentStart(
        double senderTangent,
        double tangentLength,
        double bodyTangentExtent,
        double margin)
    {
        var halfExtent = bodyTangentExtent / 2d;
        var minimumCenter = halfExtent + margin;
        var maximumCenter = Math.Max(minimumCenter, tangentLength - halfExtent - margin);
        var center = Math.Clamp(senderTangent, minimumCenter, maximumCenter);
        return center - halfExtent;
    }

    internal static int TypingFrameIndex(long tick, int framesPerSecond, int frameCount)
    {
        if (framesPerSecond <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(framesPerSecond));
        }
        if (frameCount <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(frameCount));
        }

        if (tick < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(tick));
        }

        const int intervalHundredths = 35;
        var elapsedIntervals = (tick * 100) / (framesPerSecond * intervalHundredths);
        return (int)(elapsedIntervals % frameCount);
    }

    internal static MessageBubbleTail Tail(
        OverlayEdge edge,
        RectD body,
        double senderWorldTangent,
        double tailHeight,
        double halfBase,
        double baseInset,
        double baseOverlap = 0d)
    {
        return edge switch
        {
            OverlayEdge.Bottom => HorizontalTail(
                body,
                senderWorldTangent,
                body.MaxY - baseOverlap,
                body.MaxY + tailHeight,
                halfBase,
                baseInset),
            OverlayEdge.Top => HorizontalTail(
                body,
                senderWorldTangent,
                body.MinY + baseOverlap,
                body.MinY - tailHeight,
                halfBase,
                baseInset),
            OverlayEdge.Left => VerticalTail(
                body,
                senderWorldTangent,
                body.MinX + baseOverlap,
                body.MinX - tailHeight,
                halfBase,
                baseInset),
            OverlayEdge.Right => VerticalTail(
                body,
                senderWorldTangent,
                body.MaxX - baseOverlap,
                body.MaxX + tailHeight,
                halfBase,
                baseInset),
            _ => throw new ArgumentOutOfRangeException(nameof(edge)),
        };
    }

    private static MessageBubbleTail HorizontalTail(
        RectD body,
        double senderWorldTangent,
        double baseY,
        double tipY,
        double halfBase,
        double baseInset)
    {
        var baseCenter = Math.Clamp(
            senderWorldTangent,
            body.MinX + baseInset,
            body.MaxX - baseInset);
        return new MessageBubbleTail(
            new PointD(baseCenter - halfBase, baseY),
            new PointD(senderWorldTangent, tipY),
            new PointD(baseCenter + halfBase, baseY));
    }

    private static MessageBubbleTail VerticalTail(
        RectD body,
        double senderWorldTangent,
        double baseX,
        double tipX,
        double halfBase,
        double baseInset)
    {
        var baseCenter = Math.Clamp(
            senderWorldTangent,
            body.MinY + baseInset,
            body.MaxY - baseInset);
        return new MessageBubbleTail(
            new PointD(baseX, baseCenter - halfBase),
            new PointD(tipX, senderWorldTangent),
            new PointD(baseX, baseCenter + halfBase));
    }
}
