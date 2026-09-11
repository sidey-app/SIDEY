using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;

namespace Sidey.App.Controls;

public sealed class FixedColumnPanel : Panel
{
    public int ColumnCount { get; set; } = 1;

    public double ItemHeight { get; set; } = 116d;

    protected override Size MeasureOverride(Size availableSize)
    {
        int columns = Math.Max(1, ColumnCount);
        double width;

        if (double.IsFinite(availableSize.Width))
        {
            width = Math.Max(0d, availableSize.Width);
            double itemWidth = width / columns;
            foreach (UIElement child in Children)
            {
                child.Measure(new Size(itemWidth, ItemHeight));
            }
        }
        else
        {
            double widestItem = 0d;
            foreach (UIElement child in Children)
            {
                child.Measure(new Size(double.PositiveInfinity, ItemHeight));
                widestItem = Math.Max(widestItem, child.DesiredSize.Width);
            }

            width = widestItem * columns;
        }

        int rows = (Children.Count + columns - 1) / columns;
        return new Size(width, rows * ItemHeight);
    }

    protected override Size ArrangeOverride(Size finalSize)
    {
        int columns = Math.Max(1, ColumnCount);
        double itemWidth = finalSize.Width / columns;

        for (int index = 0; index < Children.Count; index++)
        {
            int column = index % columns;
            int row = index / columns;
            Children[index].Arrange(new Rect(
                column * itemWidth,
                row * ItemHeight,
                itemWidth,
                ItemHeight));
        }

        int rows = (Children.Count + columns - 1) / columns;
        return new Size(finalSize.Width, rows * ItemHeight);
    }
}
