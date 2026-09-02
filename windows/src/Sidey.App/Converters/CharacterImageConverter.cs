using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Media.Imaging;
using Sidey.Core.Domain;

namespace Sidey.App.Converters;

public sealed class CharacterImageConverter : IValueConverter
{
    private readonly Dictionary<string, BitmapImage> _cache = [];

    public object Convert(object value, Type targetType, object parameter, string language)
    {
        string characterId = PixelCharacterCatalog.NormalizeId(value as string);
        if (_cache.TryGetValue(characterId, out BitmapImage? image))
        {
            return image;
        }

        string deploymentRoot = Sidey.Platform.Windows.SideyDeploymentPaths.DeploymentRoot();
        var uri = new Uri(Path.Combine(
            deploymentRoot,
            "Assets",
            "Characters",
            characterId,
            "sprite.png"));
        image = new BitmapImage(uri);
        _cache[characterId] = image;
        return image;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) =>
        throw new NotSupportedException();
}
