using System.Text.Json;
using Sidey.Overlay;

namespace Sidey.Platform.Windows.Tests;

public sealed class ValidationMetricsCollectorTests
{
    [Fact]
    public void ExportWritesACompleteReportAndReplacesTheTemporaryFile()
    {
        string directory = Path.Combine(
            Path.GetTempPath(),
            "sidey-validation-metrics-tests",
            Guid.NewGuid().ToString("N"));
        string outputPath = Path.Combine(directory, "metrics.json");

        try
        {
            var collector = new ValidationMetricsCollector(["hamster"], outputPath);
            collector.RecordFrame(TimeSpan.FromMilliseconds(12));

            string exportedPath = collector.Export();

            Assert.Equal(outputPath, exportedPath);
            Assert.True(File.Exists(outputPath));
            Assert.False(File.Exists(outputPath + ".tmp"));
            using JsonDocument report = JsonDocument.Parse(File.ReadAllText(outputPath));
            Assert.Equal(
                "one-character-renderer-validation",
                report.RootElement.GetProperty("mode").GetString());
            Assert.Equal(
                "hamster",
                report.RootElement.GetProperty("characterIds")[0].GetString());
            Assert.Single(report.RootElement.GetProperty("samples").EnumerateArray());
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }
}
