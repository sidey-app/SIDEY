using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Data;

namespace Sidey.App.Converters;

public sealed class BooleanToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        bool isVisible = value is true;
        if (parameter is string text
            && StringComparer.OrdinalIgnoreCase.Equals(text, "Invert"))
        {
            isVisible = !isVisible;
        }

        return isVisible ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) =>
        value is Visibility.Visible;
}
