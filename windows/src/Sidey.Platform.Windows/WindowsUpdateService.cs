using System.Diagnostics;
using System.Net.Http.Json;
using System.Text.RegularExpressions;
using System.Text.Json.Serialization;

namespace Sidey.Platform.Windows;

public sealed record WindowsUpdateManifest(string Channel, string Version, string Tag);

public sealed partial class WindowsUpdateService(HttpClient? httpClient = null)
{
    public const string CurrentVersion = "0.3.0-alpha.1";
    public static readonly Uri ManifestUri = new(
        "https://sidey-app.github.io/SIDEY/windows/update.json");
    public static readonly Uri ReleasesUri = new(
        "https://github.com/sidey-app/SIDEY/releases");

    private readonly HttpClient _httpClient = httpClient ?? new HttpClient();

    public async Task<WindowsUpdateManifest?> CheckAsync(
        CancellationToken cancellationToken = default)
    {
        var manifest = await _httpClient.GetFromJsonAsync<ManifestDto>(
            ManifestUri,
            cancellationToken).ConfigureAwait(false);
        if (manifest is null
            || manifest.Channel is not ("alpha" or "production")
            || string.IsNullOrWhiteSpace(manifest.Version)
            || manifest.Tag != $"v{manifest.Version}")
        {
            throw new InvalidDataException("SIDEY Windows 업데이트 manifest가 올바르지 않습니다.");
        }

        return IsNewerVersion(manifest.Version, CurrentVersion)
            ? new WindowsUpdateManifest(manifest.Channel, manifest.Version, manifest.Tag)
            : null;
    }

    public static bool IsNewerVersion(string candidate, string current)
    {
        var candidateVersion = ParsedVersion.Parse(candidate);
        var currentVersion = ParsedVersion.Parse(current);
        return candidateVersion.CompareTo(currentVersion) > 0;
    }

    public void OpenOfficialReleasesPage()
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Windows shell is required.");
        }

        Process.Start(new ProcessStartInfo(ReleasesUri.AbsoluteUri) { UseShellExecute = true });
    }

    private sealed record ManifestDto(
        [property: JsonPropertyName("channel")] string Channel,
        [property: JsonPropertyName("version")] string Version,
        [property: JsonPropertyName("tag")] string Tag);

    private sealed partial record ParsedVersion(
        int Major,
        int Minor,
        int Patch,
        IReadOnlyList<string> Prerelease) : IComparable<ParsedVersion>
    {
        public static ParsedVersion Parse(string value)
        {
            var match = VersionPattern().Match(value);
            if (!match.Success)
            {
                throw new InvalidDataException($"SIDEY Windows version is not valid SemVer: {value}");
            }

            var prerelease = match.Groups["pre"].Success
                ? match.Groups["pre"].Value.Split('.', StringSplitOptions.RemoveEmptyEntries)
                : Array.Empty<string>();
            return new ParsedVersion(
                int.Parse(match.Groups["major"].Value, System.Globalization.CultureInfo.InvariantCulture),
                int.Parse(match.Groups["minor"].Value, System.Globalization.CultureInfo.InvariantCulture),
                int.Parse(match.Groups["patch"].Value, System.Globalization.CultureInfo.InvariantCulture),
                prerelease);
        }

        public int CompareTo(ParsedVersion? other)
        {
            if (other is null)
            {
                return 1;
            }

            var core = Major.CompareTo(other.Major);
            if (core == 0) core = Minor.CompareTo(other.Minor);
            if (core == 0) core = Patch.CompareTo(other.Patch);
            if (core != 0)
            {
                return core;
            }

            if (Prerelease.Count == 0 || other.Prerelease.Count == 0)
            {
                return Prerelease.Count == other.Prerelease.Count
                    ? 0
                    : Prerelease.Count == 0 ? 1 : -1;
            }

            for (var index = 0; index < Math.Min(Prerelease.Count, other.Prerelease.Count); index++)
            {
                var candidateNumeric = int.TryParse(
                    Prerelease[index],
                    System.Globalization.NumberStyles.None,
                    System.Globalization.CultureInfo.InvariantCulture,
                    out var candidateNumber);
                var currentNumeric = int.TryParse(
                    other.Prerelease[index],
                    System.Globalization.NumberStyles.None,
                    System.Globalization.CultureInfo.InvariantCulture,
                    out var currentNumber);
                int result;
                if (candidateNumeric && currentNumeric)
                {
                    result = candidateNumber.CompareTo(currentNumber);
                }
                else if (candidateNumeric != currentNumeric)
                {
                    result = candidateNumeric ? -1 : 1;
                }
                else
                {
                    result = StringComparer.Ordinal.Compare(Prerelease[index], other.Prerelease[index]);
                }

                if (result != 0)
                {
                    return result;
                }
            }

            return Prerelease.Count.CompareTo(other.Prerelease.Count);
        }

        [GeneratedRegex(
            @"^(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)(?:-(?<pre>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$",
            RegexOptions.CultureInvariant)]
        private static partial Regex VersionPattern();
    }
}
