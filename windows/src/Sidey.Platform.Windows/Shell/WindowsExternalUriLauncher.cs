using System.Diagnostics;

namespace Sidey.Platform.Windows.Shell;

public static class WindowsExternalUriLauncher
{
    public static void Open(Uri uri) => Open(uri, start =>
    {
        // An existing browser can handle the URI without creating a new process.
        using var process = Process.Start(start);
    });

    internal static void Open(Uri uri, Action<ProcessStartInfo> launch)
    {
        ArgumentNullException.ThrowIfNull(uri);
        ArgumentNullException.ThrowIfNull(launch);
        if (!uri.IsAbsoluteUri)
        {
            throw new ArgumentException("An absolute URI is required.", nameof(uri));
        }

        launch(new ProcessStartInfo(uri.AbsoluteUri)
        {
            UseShellExecute = true,
        });
    }
}
