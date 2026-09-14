using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.Foundation;

namespace Sidey.App.Controls;

/// <summary>Places a description beside its editor only when both fit comfortably.</summary>
public sealed class ResponsiveFormPanel : Panel
{
    public ResponsiveFormPanel()
    {
        AnimationsEnabled = new Windows.UI.ViewManagement.UISettings().AnimationsEnabled;
        Loaded += (_, _) => AnimationsEnabled = new Windows.UI.ViewManagement.UISettings().AnimationsEnabled;
    }

    private const double EditorWidth = 320;
    private const double HorizontalSpacing = 24;
    private const double VerticalSpacing = 12;
    private bool _stacked;
    private double _labelHeight;
    private double _editorHeight;

    public bool AnimationsEnabled
    {
        get => ChildrenTransitions is { Count: > 0 };
        set => ChildrenTransitions = value
            ? [new RepositionThemeTransition()]
            : null;
    }

    protected override Size MeasureOverride(Size availableSize)
    {
        double width = double.IsFinite(availableSize.Width) ? Math.Max(0, availableSize.Width) : 640;
        _stacked = width < 560;
        _labelHeight = 0;
        _editorHeight = 0;
        if (Children.Count > 0)
        {
            Children[0].Measure(new Size(_stacked ? width : width - EditorWidth - HorizontalSpacing,
                double.PositiveInfinity));
            _labelHeight = Children[0].DesiredSize.Height;
        }
        if (Children.Count > 1)
        {
            Children[1].Measure(new Size(_stacked ? width : EditorWidth, double.PositiveInfinity));
            _editorHeight = Children[1].DesiredSize.Height;
        }
        return new Size(width, _stacked
            ? _labelHeight + VerticalSpacing + _editorHeight
            : Math.Max(_labelHeight, _editorHeight));
    }

    protected override Size ArrangeOverride(Size finalSize)
    {
        if (Children.Count > 0)
            Children[0].Arrange(new Rect(0, 0,
                _stacked ? finalSize.Width : Math.Max(0, finalSize.Width - EditorWidth - HorizontalSpacing),
                _labelHeight));
        if (Children.Count > 1)
            Children[1].Arrange(new Rect(_stacked ? 0 : Math.Max(0, finalSize.Width - EditorWidth),
                _stacked ? _labelHeight + VerticalSpacing : 0,
                _stacked ? finalSize.Width : EditorWidth, _editorHeight));
        return finalSize;
    }
}
