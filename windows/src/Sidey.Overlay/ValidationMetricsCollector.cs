using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace Sidey.Overlay;

public sealed record ValidationMetricSample(
    double ElapsedSeconds,
    double FrameMilliseconds,
    long WorkingSetBytes,
    uint GdiHandles,
    uint UserHandles);

public sealed record ValidationMetricsReport(
    DateTimeOffset StartedAt,
    DateTimeOffset FinishedAt,
    string Mode,
    IReadOnlyList<string> CharacterIds,
    IReadOnlyList<ValidationMetricSample> Samples,
    string ManualResult = "not_run");

public sealed record ValidationMetricsSummary(
    double ElapsedSeconds,
    int SampleCount,
    double MaximumFrameMilliseconds,
    long CurrentWorkingSetBytes,
    long PeakWorkingSetBytes,
    uint MaximumGdiHandles,
    uint MaximumUserHandles);

public sealed class ValidationMetricsCollector(
    IReadOnlyList<string> characterIds,
    string? outputPath = null)
{
    private const uint GdiObjects = 0;
    private const uint UserObjects = 1;
    private readonly object _gate = new();
    private readonly Stopwatch _uptime = Stopwatch.StartNew();
    private readonly DateTimeOffset _startedAt = DateTimeOffset.UtcNow;
    private readonly List<ValidationMetricSample> _samples = [];
    private readonly IReadOnlyList<string> _characterIds = characterIds.ToArray();
    private readonly string _outputPath = outputPath ?? DefaultOutputPath();
    private double _lastSampleSecond = -1d;
    private double _intervalMaximumFrameMilliseconds;

    public string OutputPath => _outputPath;

    internal void RecordFrame(TimeSpan duration)
    {
        var elapsed = _uptime.Elapsed.TotalSeconds;
        lock (_gate)
        {
            _intervalMaximumFrameMilliseconds = Math.Max(
                _intervalMaximumFrameMilliseconds,
                duration.TotalMilliseconds);
            if (Math.Floor(elapsed) <= Math.Floor(_lastSampleSecond))
            {
                return;
            }

            _lastSampleSecond = elapsed;
            using var process = Process.GetCurrentProcess();
            _samples.Add(new ValidationMetricSample(
                elapsed,
                _intervalMaximumFrameMilliseconds,
                process.WorkingSet64,
                OperatingSystem.IsWindows() ? GetGuiResources(process.Handle, GdiObjects) : 0,
                OperatingSystem.IsWindows() ? GetGuiResources(process.Handle, UserObjects) : 0));
            _intervalMaximumFrameMilliseconds = 0d;
        }
    }

    public ValidationMetricsSummary Snapshot()
    {
        lock (_gate)
        {
            var last = _samples.LastOrDefault();
            return new ValidationMetricsSummary(
                _uptime.Elapsed.TotalSeconds,
                _samples.Count,
                Math.Max(
                    _intervalMaximumFrameMilliseconds,
                    _samples.Count == 0 ? 0d : _samples.Max(sample => sample.FrameMilliseconds)),
                last?.WorkingSetBytes ?? 0,
                _samples.Count == 0 ? 0 : _samples.Max(sample => sample.WorkingSetBytes),
                _samples.Count == 0 ? 0 : _samples.Max(sample => sample.GdiHandles),
                _samples.Count == 0 ? 0 : _samples.Max(sample => sample.UserHandles));
        }
    }

    public async Task<string> ExportAsync(CancellationToken cancellationToken = default)
    {
        ValidationMetricSample[] samples;
        lock (_gate)
        {
            samples = _samples.ToArray();
        }

        var report = new ValidationMetricsReport(
            _startedAt,
            DateTimeOffset.UtcNow,
            "one-character-renderer-validation",
            _characterIds,
            samples);
        var directory = Path.GetDirectoryName(_outputPath)
            ?? throw new InvalidOperationException("Validation output directory is invalid.");
        Directory.CreateDirectory(directory);
        var temporary = _outputPath + ".tmp";
        await using (var stream = new FileStream(
            temporary,
            FileMode.Create,
            FileAccess.Write,
            FileShare.None,
            4096,
            FileOptions.Asynchronous | FileOptions.WriteThrough))
        {
            await JsonSerializer.SerializeAsync(
                stream,
                report,
                new JsonSerializerOptions(JsonSerializerDefaults.Web) { WriteIndented = true },
                cancellationToken).ConfigureAwait(false);
            await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
        }

        File.Move(temporary, _outputPath, overwrite: true);
        return _outputPath;
    }

    private static string DefaultOutputPath() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "SIDEY",
        "Validation",
        $"windows-renderer-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss}.json");

    [DllImport("user32.dll")]
    private static extern uint GetGuiResources(nint process, uint flags);
}
