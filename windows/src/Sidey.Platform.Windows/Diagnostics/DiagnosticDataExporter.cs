using System.IO.Compression;
using Sidey.Core.Storage;

namespace Sidey.Platform.Windows.Diagnostics;

public sealed class DiagnosticDataExporter
{
    private readonly string _logDirectory;
    private readonly string _destinationDirectory;
    private readonly Func<DateTimeOffset> _clock;

    public DiagnosticDataExporter()
        : this(
            Path.Combine(SideyStoragePaths.LocalApplicationDataRoot(), "SIDEY", "Logs"),
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
            () => DateTimeOffset.Now)
    {
    }

    internal DiagnosticDataExporter(
        string logDirectory,
        string destinationDirectory,
        Func<DateTimeOffset> clock)
    {
        _logDirectory = Path.GetFullPath(logDirectory);
        _destinationDirectory = Path.GetFullPath(destinationDirectory);
        _clock = clock ?? throw new ArgumentNullException(nameof(clock));
    }

    public async Task<string> ExportAsync(CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(_destinationDirectory);
        string destinationPath = AvailableDestinationPath(_clock());
        string temporaryPath = destinationPath + ".tmp";

        try
        {
            await Task.Run(() => CreateArchive(temporaryPath, cancellationToken), cancellationToken);
            File.Move(temporaryPath, destinationPath);
            return destinationPath;
        }
        catch
        {
            TryDelete(temporaryPath);
            throw;
        }
    }

    private void CreateArchive(string path, CancellationToken cancellationToken)
    {
        using ZipArchive archive = ZipFile.Open(path, ZipArchiveMode.Create);
        if (!Directory.Exists(_logDirectory))
        {
            return;
        }

        foreach (FileInfo log in new DirectoryInfo(_logDirectory)
                     .EnumerateFiles("SIDEY.*.log", SearchOption.TopDirectoryOnly)
                     .OrderBy(file => file.Name, StringComparer.OrdinalIgnoreCase))
        {
            cancellationToken.ThrowIfCancellationRequested();
            if ((log.Attributes & FileAttributes.ReparsePoint) != 0)
            {
                continue;
            }

            archive.CreateEntryFromFile(log.FullName, log.Name, CompressionLevel.Optimal);
        }
    }

    private string AvailableDestinationPath(DateTimeOffset timestamp)
    {
        string baseName = $"SIDEY-Diagnostics-{timestamp:yyyyMMdd-HHmmss}";
        string candidate = Path.Combine(_destinationDirectory, baseName + ".zip");
        for (int suffix = 2; File.Exists(candidate); suffix++)
        {
            candidate = Path.Combine(_destinationDirectory, $"{baseName}-{suffix}.zip");
        }

        return candidate;
    }

    private static void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}
