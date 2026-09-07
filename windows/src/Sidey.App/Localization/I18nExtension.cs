using System.ComponentModel;
using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Markup;
using Sidey.Core.Localization;

namespace Sidey.App.Localization;

[MarkupExtensionReturnType(ReturnType = typeof(LocalizedText))]
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
        return new LocalizedText(Key);
    }
}

[Microsoft.UI.Xaml.Data.Bindable]
public sealed class LocalizedText : INotifyPropertyChanged
{
    // Bindings own their text sources. This registry must not keep closed windows alive.
    private static readonly List<WeakReference<LocalizedText>> Sources = [];
    private readonly string _key;

    public LocalizedText(string key)
    {
        _key = key;
        if (Sources.Count % 64 == 0)
            Sources.RemoveAll(source => !source.TryGetTarget(out _));
        Sources.Add(new WeakReference<LocalizedText>(this));
    }

    public string Value => I18n.Get(_key);
    public event PropertyChangedEventHandler? PropertyChanged;

    // Called on the XAML dispatcher after the catalog has changed.
    public static void RefreshAll()
    {
        foreach (var source in Sources.ToArray())
            if (source.TryGetTarget(out var text))
                text.PropertyChanged?.Invoke(text, new PropertyChangedEventArgs(nameof(Value)));
        Sources.RemoveAll(source => !source.TryGetTarget(out _));
    }
}
