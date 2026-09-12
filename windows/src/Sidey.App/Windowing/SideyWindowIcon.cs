using Microsoft.UI.Windowing;

namespace Sidey.App.Windowing;

internal static class SideyWindowIcon
{
    internal static void Apply(AppWindow window)
    {
        string path = Path.Combine(
            SideyDeploymentPaths.DeploymentRoot(),
            "Assets",
            "Icons",
            "SideyAppIcon.ico");
        if (File.Exists(path))
        {
            window.SetIcon(path);
        }
    }
}
