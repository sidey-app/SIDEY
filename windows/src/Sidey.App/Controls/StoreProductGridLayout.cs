using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;

namespace Sidey.App.Controls;

/// <summary>
/// Measures the small store catalog in full so scrolling cannot change its extent.
/// </summary>
public sealed class StoreProductGridLayout : NonVirtualizingLayout
{
    private const double MinimumItemWidth = 150;
    private const double MinimumItemHeight = 224;
    private const double Spacing = 12;
    private const int MaximumColumns = 5;

    protected override Size MeasureOverride(NonVirtualizingLayoutContext context, Size availableSize)
    {
        LayoutMetrics metrics = MeasureItems(context, availableSize.Width);
        context.LayoutState = metrics;
        return new Size(metrics.Width, metrics.Height);
    }

    protected override Size ArrangeOverride(NonVirtualizingLayoutContext context, Size finalSize)
    {
        // Arrange must consume the preceding measure pass. Remeasuring here at
        // the rounded final width can invalidate the repeater's parent while
        // it is arranging, repeatedly alternating widths during a resize.
        if (context.LayoutState is not LayoutMetrics metrics)
            return finalSize;

        double top = 0;
        for (int row = 0; row < metrics.RowHeights.Length; row++)
        {
            for (int column = 0; column < metrics.Columns; column++)
            {
                int index = row * metrics.Columns + column;
                if (index >= Math.Min(metrics.ItemCount, context.Children.Count))
                    break;
                context.Children[index].Arrange(new Rect(
                    column * (metrics.ItemWidth + Spacing), top,
                    metrics.ItemWidth, metrics.RowHeights[row]));
            }
            top += metrics.RowHeights[row] + Spacing;
        }

        return finalSize;
    }

    private static LayoutMetrics MeasureItems(NonVirtualizingLayoutContext context, double availableWidth)
    {
        int count = context.Children.Count;
        if (count == 0)
            return new LayoutMetrics(0, 0, 1, 0, [], 0);

        double width = ResolveWidth(availableWidth, count);
        int columns = (int)Math.Clamp(
            Math.Floor((width + Spacing) / (MinimumItemWidth + Spacing)), 1, MaximumColumns);
        double itemWidth = Math.Max(0, (width - Spacing * (columns - 1)) / columns);
        double[] rowHeights = new double[(count + columns - 1) / columns];
        for (int index = 0; index < count; index++)
        {
            UIElement child = context.Children[index];
            child.Measure(new Size(itemWidth, double.PositiveInfinity));
            int row = index / columns;
            rowHeights[row] = Math.Max(rowHeights[row],
                Math.Max(MinimumItemHeight, child.DesiredSize.Height));
        }

        double height = Spacing * (rowHeights.Length - 1);
        foreach (double rowHeight in rowHeights)
            height += rowHeight;
        return new LayoutMetrics(count, width, columns, itemWidth, rowHeights, height);
    }

    private static double ResolveWidth(double availableWidth, int itemCount)
    {
        if (itemCount == 0)
            return 0;
        if (double.IsFinite(availableWidth))
            return Math.Max(0, availableWidth);

        int columns = Math.Min(itemCount, MaximumColumns);
        return MinimumItemWidth * columns + Spacing * (columns - 1);
    }

    private sealed record LayoutMetrics(
        int ItemCount, double Width, int Columns, double ItemWidth, double[] RowHeights, double Height);
}
