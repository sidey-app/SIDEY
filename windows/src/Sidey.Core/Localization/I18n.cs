using System.Globalization;
using System.Text.Json;

namespace Sidey.Core.Localization;

/// <summary>
/// Loads SIDEY's JSON language catalogs and resolves dotted i18n keys.
/// </summary>
public static class I18n
{
    public const string DefaultLanguage = "ko-KR";

    private static readonly Lock s_syncRoot = new();
    private static IReadOnlyDictionary<string, string>? s_strings;
    private static string? s_languageOverride;
    private static string? s_catalogRootOverride;

    public static string Language => ResolveLanguage();
    public static CultureInfo Culture => CultureInfo.GetCultureInfo(Language);

    public static string Get(string key)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);

        IReadOnlyDictionary<string, string> catalog = GetCatalog();
        return catalog.TryGetValue(key, out string? value) ? value : key;
    }

    public static string Format(string key, params object?[] args)
    {
        return string.Format(Culture, Get(key), args);
    }

    public static void SetLanguage(string? language)
    {
        lock (s_syncRoot)
        {
            s_languageOverride = string.IsNullOrWhiteSpace(language) ? null : language;
            s_strings = null;
        }
    }

    public static void SetCatalogRoot(string? catalogRoot)
    {
        lock (s_syncRoot)
        {
            s_catalogRootOverride = string.IsNullOrWhiteSpace(catalogRoot)
                ? null
                : Path.GetFullPath(catalogRoot);
            s_strings = null;
        }
    }

    private static IReadOnlyDictionary<string, string> GetCatalog()
    {
        lock (s_syncRoot)
        {
            return s_strings ??= LoadCatalog();
        }
    }

    private static IReadOnlyDictionary<string, string> LoadCatalog()
    {
        var catalog = new Dictionary<string, string>(StringComparer.Ordinal);
        string root = s_catalogRootOverride ?? FindCatalogRoot();

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
        string requested = s_languageOverride
            ?? Environment.GetEnvironmentVariable("SIDEY_LANGUAGE")
            ?? CultureInfo.CurrentUICulture.Name;

        if (requested.StartsWith("en", StringComparison.OrdinalIgnoreCase))
        {
            return "en-US";
        }
        if (requested.StartsWith("ja", StringComparison.OrdinalIgnoreCase))
        {
            return "ja-JP";
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

        using var document = JsonDocument.Parse(
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
