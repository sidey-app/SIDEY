using System;
using System.Linq;

namespace Sidey.Installer
{
    // Also compiled with the Windows .NET Framework compiler: do not require .NET 10.
    public sealed class InstallerLanguage
    {
        public readonly int Id;
        public readonly string EnglishName;
        public readonly string DisplayName;

        public InstallerLanguage(int id, string englishName, string displayName)
        {
            Id = id;
            EnglishName = englishName;
            DisplayName = displayName;
        }

        public override string ToString()
        {
            return DisplayName;
        }
    }

    public static class InstallerLanguages
    {
        public static InstallerLanguage[] All()
        {
            return new[]
            {
                new InstallerLanguage(2052, "Chinese (Simplified)", "简体中文"),
                new InstallerLanguage(1028, "Chinese (Traditional)", "繁體中文"),
                new InstallerLanguage(1033, "English", "English"),
                new InstallerLanguage(1041, "Japanese", "日本語"),
                new InstallerLanguage(1042, "Korean", "한국어"),
                new InstallerLanguage(1049, "Russian", "Русский"),
                new InstallerLanguage(1058, "Ukrainian", "Українська"),
            };
        }

        public static int MatchSystemLanguage(int windowsLanguage)
        {
            switch (windowsLanguage & 0x3ff)
            {
                case 0x09:
                    return 1033; // English, any region
                case 0x11:
                    return 1041;
                case 0x12:
                    return 1042;
                case 0x19:
                    return 1049;
                case 0x22:
                    return 1058;
                case 0x04:
                    // Taiwan, Hong Kong, Macau, or the neutral zh-Hant locale.
                    return windowsLanguage == 0x0404 || windowsLanguage == 0x0c04
                        || windowsLanguage == 0x1404 || windowsLanguage == 0x7c04
                            ? 1028
                            : 2052;
                default:
                    return 0;
            }
        }

        public static InstallerLanguage[] Ordered(int windowsLanguage)
        {
            int systemLanguage = MatchSystemLanguage(windowsLanguage);
            return All()
                .OrderBy(language => language.Id == systemLanguage ? 0 : 1)
                .ThenBy(language => language.EnglishName, StringComparer.Ordinal)
                .ToArray();
        }

        public static int DefaultSelection(int windowsLanguage, int savedLanguage)
        {
            if (All().Any(language => language.Id == savedLanguage))
            {
                return savedLanguage;
            }

            int systemLanguage = MatchSystemLanguage(windowsLanguage);
            return systemLanguage == 0 ? 1033 : systemLanguage;
        }
    }
}
