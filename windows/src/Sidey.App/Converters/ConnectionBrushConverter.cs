using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Media;

namespace Sidey.App.Converters;

public sealed class ConnectionBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language) =>
        new SolidColorBrush(value is true
            ? Windows.UI.Color.FromArgb(255, 34, 197, 94)
            : Windows.UI.Color.FromArgb(255, 156, 163, 175));

    public object ConvertBack(object value, Type targetType, object parameter, string language) =>
        throw new NotSupportedException();
}
