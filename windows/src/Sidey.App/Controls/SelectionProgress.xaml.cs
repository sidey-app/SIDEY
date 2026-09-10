using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;

namespace Sidey.App.Controls;

public sealed partial class SelectionProgress : UserControl
{
    public static readonly DependencyProperty IsPendingProperty = DependencyProperty.Register(nameof(IsPending), typeof(bool), typeof(SelectionProgress), new PropertyMetadata(false, OnChanged));
    public static readonly DependencyProperty AnimationsEnabledProperty = DependencyProperty.Register(nameof(AnimationsEnabled), typeof(bool), typeof(SelectionProgress), new PropertyMetadata(true, OnChanged));
    public bool IsPending { get => (bool)GetValue(IsPendingProperty); set => SetValue(IsPendingProperty, value); }
    public bool AnimationsEnabled { get => (bool)GetValue(AnimationsEnabledProperty); set => SetValue(AnimationsEnabledProperty, value); }
    public SelectionProgress() { InitializeComponent(); Loaded += (_, _) => Refresh(); }
    private static void OnChanged(DependencyObject sender, DependencyPropertyChangedEventArgs args) => ((SelectionProgress)sender).Refresh();
    private void Refresh()
    {
        if (Surface is null)
            return;
        Surface.Visibility = IsPending ? Visibility.Visible : Visibility.Collapsed;
        Visibility = Surface.Visibility;
        Ring.IsActive = IsPending && AnimationsEnabled;
        Ring.Visibility = AnimationsEnabled ? Visibility.Visible : Visibility.Collapsed;
        Label.Visibility = AnimationsEnabled ? Visibility.Collapsed : Visibility.Visible;
        AutomationProperties.SetLiveSetting(this, AutomationLiveSetting.Polite);
    }
}
