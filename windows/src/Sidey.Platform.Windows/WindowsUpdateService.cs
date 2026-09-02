using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Sidey.Core.Localization;

namespace Sidey.Platform.Windows;

public sealed record WindowsUpdateManifest(
    string Channel,
    string Version,
    string Tag,
    Uri InstallerUri,
    string Sha256);

public sealed partial class WindowsUpdateService(HttpClient? httpClient = null)
{
    public const string CurrentVersion = "1.0.3";
    public static readonly Uri ManifestUri = new(
        "https://sidey-app.github.io/SIDEY/windows-latest.json");
    private readonly HttpClient _httpClient = httpClient ?? new HttpClient();

    public async Task<WindowsUpdateManifest?> CheckAsync(
        CancellationToken cancellationToken = default)
    {
        ManifestDto? manifest;
        try
        {
            manifest = await _httpClient.GetFromJsonAsync<ManifestDto>(
                ManifestUri,
                cancellationToken).ConfigureAwait(false);
        }
        catch (HttpRequestException exception) when (exception.StatusCode == HttpStatusCode.NotFound)
        {
            throw new InvalidOperationException(
                I18n.Get("update.notPublished"),
                exception);
        }
        if (manifest is null
            || manifest.Channel is not ("alpha" or "production")
            || string.IsNullOrWhiteSpace(manifest.Version)
            || manifest.Tag != $"windows-v{manifest.Version}")
        {
            throw new InvalidDataException(I18n.Get("update.invalidManifest"));
        }

        if (!IsNewerVersion(manifest.Version, CurrentVersion))
        {
            return null;
        }

        var expectedInstallerUri = new Uri(
            $"https://github.com/sidey-app/SIDEY/releases/download/{manifest.Tag}/" +
            $"SIDEY-Windows-x64-v{manifest.Version}.msi");
        if (!Uri.TryCreate(manifest.InstallerUrl, UriKind.Absolute, out Uri? installerUri)
            || installerUri != expectedInstallerUri
            || string.IsNullOrWhiteSpace(manifest.Sha256)
            || !Sha256Pattern().IsMatch(manifest.Sha256))
        {
            throw new InvalidDataException(
                I18n.Get("update.invalidInstaller"));
        }

        return new WindowsUpdateManifest(
            manifest.Channel,
            manifest.Version,
            manifest.Tag,
            installerUri,
            manifest.Sha256.ToLowerInvariant());
    }

    public async Task<string> DownloadInstallerAsync(
        WindowsUpdateManifest manifest,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        string updateDirectory = Path.Combine(
            Path.GetTempPath(),
            "SIDEY",
            "Updates",
            manifest.Version);
        Directory.CreateDirectory(updateDirectory);
        string installerPath = Path.Combine(
            updateDirectory,
            Path.GetFileName(manifest.InstallerUri.LocalPath));
        string partialPath = $"{installerPath}.download";

        try
        {
            using HttpResponseMessage response = await _httpClient.GetAsync(
                manifest.InstallerUri,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken).ConfigureAwait(false);
            response.EnsureSuccessStatusCode();
            await using (Stream source = await response.Content.ReadAsStreamAsync(
                cancellationToken).ConfigureAwait(false))
            await using (var destination = new FileStream(
                partialPath,
                FileMode.Create,
                FileAccess.Write,
                FileShare.None,
                bufferSize: 81920,
                useAsync: true))
            {
                await source.CopyToAsync(destination, cancellationToken).ConfigureAwait(false);
            }

            await using var downloaded = File.OpenRead(partialPath);
            byte[] digest = await SHA256.HashDataAsync(downloaded, cancellationToken)
                .ConfigureAwait(false);
            string actualHash = Convert.ToHexStringLower(digest);
            if (!StringComparer.OrdinalIgnoreCase.Equals(actualHash, manifest.Sha256))
            {
                throw new InvalidDataException(
                    I18n.Get("update.hashMismatch"));
            }

            File.Move(partialPath, installerPath, overwrite: true);
            return installerPath;
        }
        catch
        {
            File.Delete(partialPath);
            throw;
        }
    }

    public static void LaunchInstaller(string installerPath)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Windows shell is required.");
        }

        Process.Start(new ProcessStartInfo(installerPath) { UseShellExecute = true });
    }

    public static bool IsNewerVersion(string candidate, string current)
    {
        var candidateVersion = ParsedVersion.Parse(candidate);
        var currentVersion = ParsedVersion.Parse(current);
        return candidateVersion.CompareTo(currentVersion) > 0;
    }

    private sealed record ManifestDto(
        [property: JsonPropertyName("channel")] string Channel,
        [property: JsonPropertyName("version")] string Version,
        [property: JsonPropertyName("tag")] string Tag,
        [property: JsonPropertyName("installer_url")] string? InstallerUrl,
        [property: JsonPropertyName("sha256")] string? Sha256);

    [GeneratedRegex("^[0-9a-fA-F]{64}$", RegexOptions.CultureInvariant)]
    private static partial Regex Sha256Pattern();

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
            if (core == 0)
                core = Minor.CompareTo(other.Minor);
            if (core == 0)
                core = Patch.CompareTo(other.Patch);
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
