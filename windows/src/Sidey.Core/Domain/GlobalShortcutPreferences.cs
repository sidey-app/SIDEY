namespace Sidey.Core.Domain;

public enum GlobalShortcutAction
{
    Compose = 0,
    ToggleOverlay = 1,
    ToggleQuietMode = 2,
}

public enum GlobalShortcutRegistrationStatus
{
    NotSet = 0,
    Registered = 1,
    InUse = 2,
    Unavailable = 3,
}

/// <summary>
/// Keeps each combination as text so an unreadable value is dropped instead of
/// making the whole preferences file unreadable. No combination is assigned by default.
/// </summary>
public sealed record GlobalShortcutPreferences
{
    public static GlobalShortcutPreferences Empty { get; } = new();

    public static IReadOnlyList<GlobalShortcutAction> Actions { get; } =
    [
        GlobalShortcutAction.Compose,
        GlobalShortcutAction.ToggleOverlay,
        GlobalShortcutAction.ToggleQuietMode,
    ];

    public string? Compose { get; init; }

    public string? ToggleOverlay { get; init; }

    public string? ToggleQuietMode { get; init; }

    public GlobalShortcut? Get(GlobalShortcutAction action) =>
        GlobalShortcut.TryParse(Text(action), out GlobalShortcut shortcut)
        && shortcut.Validate() == GlobalShortcutValidation.Valid
            ? shortcut
            : null;

    public GlobalShortcutPreferences With(GlobalShortcutAction action, GlobalShortcut? shortcut)
    {
        string? text = shortcut?.ToString();
        return action switch
        {
            GlobalShortcutAction.Compose => this with { Compose = text },
            GlobalShortcutAction.ToggleOverlay => this with { ToggleOverlay = text },
            GlobalShortcutAction.ToggleQuietMode => this with { ToggleQuietMode = text },
            _ => throw new ArgumentOutOfRangeException(nameof(action)),
        };
    }

    public GlobalShortcutAction? FindAction(GlobalShortcut shortcut)
    {
        foreach (GlobalShortcutAction action in Actions)
        {
            if (Get(action) == shortcut)
            {
                return action;
            }
        }

        return null;
    }

    /// <summary>Drops unusable text and keeps a repeated combination only for the first action.</summary>
    public GlobalShortcutPreferences Normalize()
    {
        GlobalShortcutPreferences normalized = Empty;
        foreach (GlobalShortcutAction action in Actions)
        {
            if (Get(action) is { } shortcut && normalized.FindAction(shortcut) is null)
            {
                normalized = normalized.With(action, shortcut);
            }
        }

        return normalized;
    }

    private string? Text(GlobalShortcutAction action) => action switch
    {
        GlobalShortcutAction.Compose => Compose,
        GlobalShortcutAction.ToggleOverlay => ToggleOverlay,
        GlobalShortcutAction.ToggleQuietMode => ToggleQuietMode,
        _ => null,
    };
}
