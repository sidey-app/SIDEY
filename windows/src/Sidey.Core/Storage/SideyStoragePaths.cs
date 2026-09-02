namespace Sidey.Core.Storage;

public static class SideyStoragePaths
{
    public const string SmokeRootEnvironmentVariable = "SIDEY_STARTUP_SMOKE_DATA_ROOT";

    public static string LocalApplicationDataRoot()
    {
        string? smokeRoot = Environment.GetEnvironmentVariable(
            SmokeRootEnvironmentVariable,
            EnvironmentVariableTarget.Process);
        return string.IsNullOrWhiteSpace(smokeRoot)
            ? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)
            : Path.GetFullPath(smokeRoot);
    }
}
