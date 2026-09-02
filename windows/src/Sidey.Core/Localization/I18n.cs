using System.Globalization;
using System.Text.Json;

namespace Sidey.Core.Localization;

/// <summary>
/// Loads SIDEY's JSON language catalogs and resolves dotted i18n keys.
/// </summary>
public static class I18n
{
    public const string DefaultLanguage = "ko-KR";

    private static readonly object SyncRoot = new();
    private static IReadOnlyDictionary<string, string>? strings;
    private static string? languageOverride;
    private static string? catalogRootOverride;

    public static string Language => ResolveLanguage();

    public static string Get(string key)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);

        IReadOnlyDictionary<string, string> catalog = GetCatalog();
        return catalog.TryGetValue(key, out string? value) ? value : key;
    }

    public static string Format(string key, params object?[] args)
    {
        return string.Format(CultureInfo.CurrentCulture, Get(key), args);
    }

    public static void SetLanguage(string? language)
    {
        lock (SyncRoot)
        {
            languageOverride = string.IsNullOrWhiteSpace(language) ? null : language;
            strings = null;
        }
    }

    public static void SetCatalogRoot(string? catalogRoot)
    {
        lock (SyncRoot)
        {
            catalogRootOverride = string.IsNullOrWhiteSpace(catalogRoot)
                ? null
                : Path.GetFullPath(catalogRoot);
            strings = null;
        }
    }

    private static IReadOnlyDictionary<string, string> GetCatalog()
    {
        lock (SyncRoot)
        {
            return strings ??= LoadCatalog();
        }
    }

    private static IReadOnlyDictionary<string, string> LoadCatalog()
    {
        var catalog = new Dictionary<string, string>(StringComparer.Ordinal);
        string root = catalogRootOverride ?? FindCatalogRoot();

        LoadFile(Path.Combine(root, $"{DefaultLanguage}.json"), catalog);

        string language = ResolveLanguage();
        if (!string.Equals(language, DefaultLanguage, StringComparison.OrdinalIgnoreCase))
        {
            LoadFile(Path.Combine(root, $"{language}.json"), catalog);
        }

        return catalog;
    }

    private static string ResolveLanguage()
    {
        string requested = languageOverride
            ?? Environment.GetEnvironmentVariable("SIDEY_LANGUAGE")
            ?? CultureInfo.CurrentUICulture.Name;

        if (requested.StartsWith("en", StringComparison.OrdinalIgnoreCase))
        {
            return "en-US";
        }

        return DefaultLanguage;
    }

    private static string FindCatalogRoot()
    {
        string baseDirectory = Path.GetFullPath(AppContext.BaseDirectory);
        string local = Path.Combine(baseDirectory, "Langs");
        if (Directory.Exists(local))
        {
            return local;
        }

        DirectoryInfo? directory = Directory.GetParent(baseDirectory.TrimEnd(Path.DirectorySeparatorChar));
        if (directory is not null)
        {
            string besideRuntime = Path.Combine(directory.FullName, "Langs");
            if (Directory.Exists(besideRuntime))
            {
                return besideRuntime;
            }
        }

        return local;
    }

    private static void LoadFile(string path, IDictionary<string, string> target)
    {
        if (!File.Exists(path))
        {
            return;
        }

        using JsonDocument document = JsonDocument.Parse(
            File.ReadAllText(path),
            new JsonDocumentOptions { AllowTrailingCommas = true, CommentHandling = JsonCommentHandling.Skip });
        Flatten(document.RootElement, null, target);
    }

    private static void Flatten(JsonElement element, string? prefix, IDictionary<string, string> target)
    {
        foreach (JsonProperty property in element.EnumerateObject())
        {
            string key = string.IsNullOrEmpty(prefix) ? property.Name : $"{prefix}.{property.Name}";
            if (property.Value.ValueKind == JsonValueKind.Object)
            {
                Flatten(property.Value, key, target);
            }
            else if (property.Value.ValueKind == JsonValueKind.String)
            {
                target[key] = property.Value.GetString() ?? string.Empty;
            }
        }
    }
}
