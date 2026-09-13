using System.IO.Compression;
using Sidey.Platform.Windows.Diagnostics;

namespace Sidey.Platform.Windows.Tests;

public sealed class DiagnosticDataExporterTests
{
    [Fact]
    public async Task ExportIncludesOnlyTopLevelSideyLogsAndDoesNotOverwriteAnExistingArchive()
    {
        string root = Path.Combine(Path.GetTempPath(), "SIDEY-DiagnosticExportTests", Guid.NewGuid().ToString("N"));
        string logs = Path.Combine(root, "logs");
        string desktop = Path.Combine(root, "desktop");
        Directory.CreateDirectory(logs);
        Directory.CreateDirectory(desktop);
        Directory.CreateDirectory(Path.Combine(logs, "nested"));
        await File.WriteAllTextAsync(Path.Combine(logs, "SIDEY.1_2_1.20260912.120000.log"), "first");
        await File.WriteAllTextAsync(Path.Combine(logs, "SIDEY.1_2_1.20260912.120100.log"), "second");
        await File.WriteAllTextAsync(Path.Combine(logs, "preferences.json"), "private settings");
        await File.WriteAllTextAsync(Path.Combine(logs, "nested", "SIDEY.nested.log"), "nested");
        await File.WriteAllTextAsync(Path.Combine(desktop, "SIDEY-Diagnostics-20260912-123456.zip"), "existing");

        try
        {
            var exporter = new DiagnosticDataExporter(
                logs,
                desktop,
                () => new DateTimeOffset(2026, 9, 12, 12, 34, 56, TimeSpan.FromHours(9)));

            string archivePath = await exporter.ExportAsync();

            Assert.Equal(
                Path.Combine(desktop, "SIDEY-Diagnostics-20260912-123456-2.zip"),
                archivePath);
            using ZipArchive archive = ZipFile.OpenRead(archivePath);
            Assert.Equal(
                ["SIDEY.1_2_1.20260912.120000.log", "SIDEY.1_2_1.20260912.120100.log"],
                archive.Entries.Select(entry => entry.FullName));
            Assert.Equal("existing", await File.ReadAllTextAsync(
                Path.Combine(desktop, "SIDEY-Diagnostics-20260912-123456.zip")));
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }
}
