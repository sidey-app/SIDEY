using System.Net;
using System.Security.Cryptography;
using System.Text;
using Sidey.Platform.Windows;

namespace Sidey.Platform.Windows.Tests;

public sealed class WindowsUpdateServiceTests
{
    [Fact]
    public async Task MissingManifestUsesAnActionableMessage()
    {
        using var client = new HttpClient(new StubHandler(
            new HttpResponseMessage(HttpStatusCode.NotFound)));
        var service = new WindowsUpdateService(client);

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(
            () => service.CheckAsync());

        Assert.Equal("Windows 업데이트 정보가 아직 게시되지 않았습니다.", exception.Message);
    }

    [Fact]
    public async Task CurrentWindowsManifestDoesNotOfferAnUpdate()
    {
        const string manifest = """
            {
              "channel": "production",
              "version": "1.0.8",
              "tag": "windows-v1.0.8"
            }
            """;
        using var response = new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(manifest, Encoding.UTF8, "application/json"),
        };
        using var client = new HttpClient(new StubHandler(response));
        var service = new WindowsUpdateService(client);

        WindowsUpdateManifest? update = await service.CheckAsync();

        Assert.Null(update);
    }

    [Fact]
    public async Task DownloadClosesTheHashStreamBeforePublishingTheInstaller()
    {
        byte[] installerBytes = Encoding.UTF8.GetBytes("SIDEY update regression fixture");
        string sha256 = Convert.ToHexStringLower(SHA256.HashData(installerBytes));
        string version = $"1.0.6-file-handle-{Guid.NewGuid():N}";
        string installerName = $"SIDEY-Windows-x64-v{version}-Setup.exe";
        string updateDirectory = Path.Combine(
            Path.GetTempPath(),
            "SIDEY",
            "Updates",
            version);
        string expectedPath = Path.Combine(updateDirectory, installerName);
        using var response = new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new ByteArrayContent(installerBytes),
        };
        using var client = new HttpClient(new StubHandler(response));
        var service = new WindowsUpdateService(client);
        var manifest = new WindowsUpdateManifest(
            "production",
            version,
            $"windows-v{version}",
            new Uri($"https://example.invalid/{installerName}"),
            sha256);

        try
        {
            string actualPath = await service.DownloadInstallerAsync(manifest);

            Assert.Equal(expectedPath, actualPath);
            Assert.Equal(installerBytes, await File.ReadAllBytesAsync(actualPath));
            Assert.False(File.Exists($"{expectedPath}.download"));
        }
        finally
        {
            if (Directory.Exists(updateDirectory))
            {
                Directory.Delete(updateDirectory, recursive: true);
            }
        }
    }

    [Fact]
    public async Task NewerManifestRequiresTheVersionedInstallerAndSha256()
    {
        const string manifest = """
            {
              "channel": "production",
              "version": "1.0.8",
              "tag": "windows-v1.0.8",
              "installer_url": "https://github.com/sidey-app/SIDEY/releases/download/windows-v1.0.8/SIDEY-Windows-x64-v1.0.8-Setup.exe",
              "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
            }
            """;
        using var response = new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(manifest, Encoding.UTF8, "application/json"),
        };
        using var client = new HttpClient(new StubHandler(response));
        var service = new WindowsUpdateService(client);

        WindowsUpdateManifest? update = await service.CheckAsync();

        Assert.NotNull(update);
        Assert.Equal("1.0.8", update.Version);
        Assert.Equal(
            "https://github.com/sidey-app/SIDEY/releases/download/windows-v1.0.8/" +
            "SIDEY-Windows-x64-v1.0.8-Setup.exe",
            update.InstallerUri.AbsoluteUri);
        Assert.Equal(
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            update.Sha256);
    }

    [Fact]
    public async Task NewerManifestWithoutInstallerMetadataIsRejected()
    {
        const string manifest = """
            {
              "channel": "production",
              "version": "1.0.7",
              "tag": "windows-v1.0.7"
            }
            """;
        using var response = new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(manifest, Encoding.UTF8, "application/json"),
        };
        using var client = new HttpClient(new StubHandler(response));
        var service = new WindowsUpdateService(client);

        await Assert.ThrowsAsync<InvalidDataException>(() => service.CheckAsync());
    }

    [Fact]
    public async Task NewerManifestRejectsTheFormerMsiContract()
    {
        const string manifest = """
            {
              "channel": "production",
              "version": "1.0.8",
              "tag": "windows-v1.0.8",
              "installer_url": "https://github.com/sidey-app/SIDEY/releases/download/windows-v1.0.8/SIDEY-Windows-x64-v1.0.8.msi",
              "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
            }
            """;
        using var response = new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(manifest, Encoding.UTF8, "application/json"),
        };
        using var client = new HttpClient(new StubHandler(response));
        var service = new WindowsUpdateService(client);

        await Assert.ThrowsAsync<InvalidDataException>(() => service.CheckAsync());
    }

    private sealed class StubHandler(HttpResponseMessage response) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            _ = request;
            _ = cancellationToken;
            return Task.FromResult(response);
        }
    }
}
