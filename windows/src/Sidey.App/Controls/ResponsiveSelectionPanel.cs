using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.Foundation;

namespace Sidey.App.Controls;

/// <summary>Fits complete selection tiles to the available card width.</summary>
public sealed class ResponsiveSelectionPanel : Panel
{
    public ResponsiveSelectionPanel()
    {
        AnimationsEnabled = new Windows.UI.ViewManagement.UISettings().AnimationsEnabled;
        Loaded += (_, _) => AnimationsEnabled = new Windows.UI.ViewManagement.UISettings().AnimationsEnabled;
    }

    private const double Spacing = 8;
    private const double MaximumItemWidth = 144;
    private int _columns = 1;
    private double _itemWidth;
    private double[] _rowHeights = [];

    public int MaximumColumns { get; set; } = 5;
    public double MinimumItemWidth { get; set; } = 128;
    public double MinimumItemHeight { get; set; } = 116;

    public bool AnimationsEnabled
    {
        get => ChildrenTransitions is { Count: > 0 };
        set => ChildrenTransitions = value
            ? [new RepositionThemeTransition { IsStaggeringEnabled = false }]
            : null;
    }

    protected override Size MeasureOverride(Size availableSize)
    {
        double width = double.IsFinite(availableSize.Width)
            ? Math.Max(0, availableSize.Width)
            : Math.Max(1, MaximumColumns) * (MinimumItemWidth + Spacing) - Spacing;
        _columns = (int)Math.Clamp(Math.Floor((width + Spacing) / (MinimumItemWidth + Spacing)),
            1, Math.Max(1, MaximumColumns));
        // Keep choices compact when a column breakpoint leaves spare space.
        // Cache the measured width so arrange cannot resize wrapped captions.
        _itemWidth = Math.Floor(Math.Clamp(
            (width - Spacing * (_columns - 1)) / _columns, 0, MaximumItemWidth));
        _rowHeights = new double[(Children.Count + _columns - 1) / _columns];
        for (int index = 0; index < Children.Count; index++)
        {
            UIElement child = Children[index];
            child.Measure(new Size(_itemWidth, double.PositiveInfinity));
            int row = index / _columns;
            _rowHeights[row] = Math.Max(_rowHeights[row],
                Math.Ceiling(Math.Max(MinimumItemHeight, child.DesiredSize.Height)));
        }
        return new Size(width, _rowHeights.Sum() + Spacing * Math.Max(0, _rowHeights.Length - 1));
    }

    protected override Size ArrangeOverride(Size finalSize)
    {
        double top = 0;
        for (int row = 0; row < _rowHeights.Length; row++)
        {
            for (int column = 0; column < _columns; column++)
            {
                int index = row * _columns + column;
                if (index >= Children.Count)
                    break;
                Children[index].Arrange(new Rect(column * (_itemWidth + Spacing), top,
                    _itemWidth, _rowHeights[row]));
            }
            top += _rowHeights[row] + Spacing;
        }
        return finalSize;
    }
}
