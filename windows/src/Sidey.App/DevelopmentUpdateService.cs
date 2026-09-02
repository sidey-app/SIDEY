using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;

namespace Sidey.App;

internal sealed record DevelopmentUpdateRequest(
    string SourceDirectory,
    string Sha256);

internal sealed class DevelopmentUpdateService : IDisposable
{
    public const string RequestFileName = ".sidey-dev-update-request.json";
    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(1);
    private readonly string _liveDirectory;
    private readonly string _requestPath;
    private readonly Action<DevelopmentUpdateRequest> _accepted;
    private readonly Timer _timer;
    private int _processing;
    private bool _disposed;

    private DevelopmentUpdateService(
        string liveDirectory,
        Action<DevelopmentUpdateRequest> accepted)
    {
        _liveDirectory = liveDirectory;
        _requestPath = Path.Combine(liveDirectory, RequestFileName);
        _accepted = accepted;
        _timer = new Timer(
            static state => ((DevelopmentUpdateService)state!).Poll(),
            this,
            PollInterval,
            PollInterval);
    }

    public static DevelopmentUpdateService? Start(Action<DevelopmentUpdateRequest> accepted)
    {
        ArgumentNullException.ThrowIfNull(accepted);
        // The WinUI host runs under Runtime, while staged update requests live
        // beside the public launcher at the deployment root.
        var liveDirectory = Sidey.Platform.Windows.SideyDeploymentPaths.DeploymentRoot()
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        return string.Equals(
            Path.GetFileName(liveDirectory),
            "live",
            StringComparison.OrdinalIgnoreCase)
            ? new DevelopmentUpdateService(liveDirectory, accepted)
            : null;
    }

    public bool LaunchUpdater(DevelopmentUpdateRequest request)
    {
        if (!TryValidate(request, out var sourceDirectory, out var expectedHash))
        {
            return false;
        }

        var updaterDirectory = Path.Combine(
            Sidey.Core.Storage.SideyStoragePaths.LocalApplicationDataRoot(),
            "SIDEY",
            "Updater");
        Directory.CreateDirectory(updaterDirectory);
        var scriptPath = Path.Combine(updaterDirectory, "apply-development-update.ps1");
        File.WriteAllText(scriptPath, UpdaterScript);

        var start = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
        };
        start.ArgumentList.Add("-NoLogo");
        start.ArgumentList.Add("-NoProfile");
        start.ArgumentList.Add("-NonInteractive");
        start.ArgumentList.Add("-WindowStyle");
        start.ArgumentList.Add("Hidden");
        start.ArgumentList.Add("-ExecutionPolicy");
        start.ArgumentList.Add("Bypass");
        start.ArgumentList.Add("-File");
        start.ArgumentList.Add(scriptPath);
        start.ArgumentList.Add("-ParentPid");
        start.ArgumentList.Add(Environment.ProcessId.ToString());
        start.ArgumentList.Add("-SourceDirectory");
        start.ArgumentList.Add(sourceDirectory);
        start.ArgumentList.Add("-DestinationDirectory");
        start.ArgumentList.Add(_liveDirectory);
        start.ArgumentList.Add("-ExpectedSha256");
        start.ArgumentList.Add(expectedHash);
        return Process.Start(start) is not null;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        _timer.Change(Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
        _timer.Dispose();
    }

    private void Poll()
    {
        if (_disposed
            || !File.Exists(_requestPath)
            || Interlocked.Exchange(ref _processing, 1) != 0)
        {
            return;
        }

        try
        {
            var request = JsonSerializer.Deserialize<DevelopmentUpdateRequest>(
                File.ReadAllText(_requestPath));
            if (request is null || !TryValidate(request, out _, out _))
            {
                return;
            }
            File.Delete(_requestPath);
            _accepted(request);
        }
        catch (Exception exception)
        {
            StartupDiagnostics.NonFatal("development-update-request", exception);
        }
        finally
        {
            Interlocked.Exchange(ref _processing, 0);
        }
    }

    private bool TryValidate(
        DevelopmentUpdateRequest request,
        out string sourceDirectory,
        out string expectedHash)
    {
        sourceDirectory = string.Empty;
        expectedHash = request.Sha256.Trim().ToUpperInvariant();
        if (expectedHash.Length != 64 || expectedHash.Any(character => !Uri.IsHexDigit(character)))
        {
            return false;
        }

        sourceDirectory = Path.GetFullPath(request.SourceDirectory)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var liveParent = Directory.GetParent(_liveDirectory)?.FullName;
        var sourceParent = Directory.GetParent(sourceDirectory)?.FullName;
        if (liveParent is null
            || sourceParent is null
            || !string.Equals(liveParent, sourceParent, StringComparison.OrdinalIgnoreCase)
            || !Path.GetFileName(sourceDirectory).StartsWith(
                "live-ready-",
                StringComparison.OrdinalIgnoreCase)
            || string.Equals(sourceDirectory, _liveDirectory, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var sourceExecutable = Path.Combine(sourceDirectory, "SIDEY.exe");
        return File.Exists(sourceExecutable)
            && string.Equals(
                FileSha256(sourceExecutable),
                expectedHash,
                StringComparison.OrdinalIgnoreCase);
    }

    private static string FileSha256(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    private const string UpdaterScript = """
param(
    [Parameter(Mandatory = $true)][int]$ParentPid,
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$DestinationDirectory,
    [Parameter(Mandatory = $true)][string]$ExpectedSha256
)
$ErrorActionPreference = 'Stop'
Wait-Process -Id $ParentPid -Timeout 10 -ErrorAction SilentlyContinue
if (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) {
    Stop-Process -Id $ParentPid -Force -ErrorAction Stop
    Wait-Process -Id $ParentPid -Timeout 10 -ErrorAction SilentlyContinue
}
if (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) { exit 2 }
$sourceExecutable = Join-Path $SourceDirectory 'SIDEY.exe'
if ((Get-FileHash -LiteralPath $sourceExecutable -Algorithm SHA256).Hash -ne $ExpectedSha256) { exit 3 }
$copyDeadline = (Get-Date).AddSeconds(20)
$copyCompleted = $false
do {
    try {
        Get-ChildItem -LiteralPath $SourceDirectory -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $DestinationDirectory -Recurse -Force -ErrorAction Stop
        }
        $copyCompleted = $true
    }
    catch {
        Start-Sleep -Milliseconds 500
    }
} while (-not $copyCompleted -and (Get-Date) -lt $copyDeadline)
if (-not $copyCompleted) { exit 5 }
$destinationExecutable = Join-Path $DestinationDirectory 'SIDEY.exe'
if ((Get-FileHash -LiteralPath $destinationExecutable -Algorithm SHA256).Hash -ne $ExpectedSha256) { exit 4 }
Start-Process -FilePath $destinationExecutable -WorkingDirectory $DestinationDirectory
""";
}
