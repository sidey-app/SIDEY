using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.UI.ViewManagement;

namespace Sidey.App.Controls;

public sealed partial class SkeletonBar : UserControl
{
    private static readonly UISettings s_userInterfaceSettings = new();
    private readonly Storyboard _pulse = new();

    public SkeletonBar()
    {
        InitializeComponent();
        var opacity = new DoubleAnimation
        {
            From = 0.38,
            To = 0.76,
            Duration = TimeSpan.FromMilliseconds(850),
            AutoReverse = true,
            RepeatBehavior = RepeatBehavior.Forever,
        };
        Storyboard.SetTarget(opacity, this);
        Storyboard.SetTargetProperty(opacity, "Opacity");
        _pulse.Children.Add(opacity);

        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
        _ = RegisterPropertyChangedCallback(
            VisibilityProperty,
            (_, _) => UpdateAnimation());
    }

    private void OnLoaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateAnimation();
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _pulse.Stop();
    }

    private void UpdateAnimation()
    {
        _pulse.Stop();
        Opacity = 0.58;
        if (IsLoaded
            && Visibility == Visibility.Visible
            && s_userInterfaceSettings.AnimationsEnabled)
        {
            _pulse.Begin();
        }
    }
}
