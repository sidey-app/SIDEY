// This test double must share the namespace used by the linked production coordinator.
#pragma warning disable IDE0130
namespace Sidey.App.Services;
#pragma warning restore IDE0130

// Exercise the production coordinator without starting an app session or writing
// to the installed user's diagnostic directory.
internal static class StartupDiagnostics
{
    public static void Stage(string stage) { }
    public static void NonFatal(string stage, Exception exception) { }
}
