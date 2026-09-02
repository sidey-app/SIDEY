using System.Runtime.CompilerServices;
using Sidey.Core.Localization;

namespace Sidey.Core.Tests;

internal static class TestLocalization
{
    [ModuleInitializer]
    internal static void Initialize() => I18n.SetLanguage("ko-KR");
}
