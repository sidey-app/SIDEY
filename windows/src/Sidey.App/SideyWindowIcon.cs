using Microsoft.UI.Windowing;

namespace Sidey.App;

internal static class SideyWindowIcon
{
    internal static void Apply(AppWindow window)
    {
        var path = Path.Combine(
            Sidey.Platform.Windows.SideyDeploymentPaths.DeploymentRoot(),
            "Assets",
            "Icons",
            "SideyAppIcon.ico");
        if (File.Exists(path))
        {
            window.SetIcon(path);
        }
    }
}
