namespace Sidey.App;

// Exercise the production coordinator without starting an app session or writing
// to the installed user's diagnostic directory.
internal static class StartupDiagnostics
{
    public static void Stage(string stage) { }
    public static void NonFatal(string stage, Exception exception) { }
}
