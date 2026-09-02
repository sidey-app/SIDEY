using Microsoft.UI.Xaml.Markup;
using Sidey.Core.Localization;

namespace Sidey.App.Localization;

[MarkupExtensionReturnType(ReturnType = typeof(string))]
public sealed class I18nExtension : MarkupExtension
{
    public I18nExtension()
    {
    }

    public I18nExtension(string key)
    {
        Key = key;
    }

    public string Key { get; set; } = string.Empty;

    protected override object ProvideValue()
    {
        return I18n.Get(Key);
    }
}
