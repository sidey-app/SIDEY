[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WebsiteDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [Parameter(Mandatory = $true)]
    [Alias('ReleaseMsi')]
    [string]$ReleaseInstaller
)

$ErrorActionPreference = 'Stop'
$resolvedWebsiteDir = (Resolve-Path -LiteralPath $WebsiteDir).Path
$resolvedReleaseInstaller = (Resolve-Path -LiteralPath $ReleaseInstaller).Path
$resolvedOutputDir = [IO.Path]::GetFullPath($OutputDir)
$sourceManifestPath = Join-Path $resolvedWebsiteDir 'windows-latest.json'
$manifest = Get-Content -LiteralPath $sourceManifestPath -Raw -Encoding UTF8 |
    ConvertFrom-Json

if ($manifest.channel -ne 'production' -or
    [string]$manifest.version -notmatch '^\d+\.\d+\.\d+$') {
    throw 'Windows Pages manifest must describe a stable production release.'
}

$version = [string]$manifest.version
$tag = "windows-v$version"
$installerName = if ([Version]::Parse($version) -le [Version]'1.0.5') {
    "SIDEY-Windows-x64-v$version.msi"
}
else {
    "SIDEY-Windows-x64-v${version}-Setup.exe"
}
$installerUrl = "https://github.com/sidey-app/SIDEY/releases/download/$tag/$installerName"
if ([string]$manifest.tag -ne $tag -or
    [string]$manifest.installer_url -ne $installerUrl) {
    throw 'Windows Pages manifest tag or installer URL does not match its version.'
}
if ([IO.Path]::GetFileName($resolvedReleaseInstaller) -ne $installerName) {
    throw "Release installer filename does not match the public contract: $installerName"
}

if (Test-Path -LiteralPath $resolvedOutputDir) {
    $existingOutput = @(Get-ChildItem -LiteralPath $resolvedOutputDir -Force)
    if ($existingOutput.Count -gt 0) {
        throw "Pages output directory must be empty: $resolvedOutputDir"
    }
}
else {
    [IO.Directory]::CreateDirectory($resolvedOutputDir) | Out-Null
}

Get-ChildItem -LiteralPath $resolvedWebsiteDir -Force |
    Copy-Item -Destination $resolvedOutputDir -Recurse -Force

$hash = (Get-FileHash -LiteralPath $resolvedReleaseInstaller -Algorithm SHA256).Hash.ToLowerInvariant()
$publishedManifest = [ordered]@{
    channel = 'production'
    version = $version
    tag = $tag
    installer_url = $installerUrl
    sha256 = $hash
}
$manifestJson = $publishedManifest | ConvertTo-Json
$utf8NoBom = [Text.UTF8Encoding]::new($false)
foreach ($relativePath in @('windows-latest.json', 'windows/update.json')) {
    $path = Join-Path $resolvedOutputDir $relativePath
    [IO.File]::WriteAllText($path, "$manifestJson`n", $utf8NoBom)
}

foreach ($relativePath in @('index.html', 'en/index.html')) {
    $path = Join-Path $resolvedOutputDir $relativePath
    $html = [IO.File]::ReadAllText($path)
    foreach ($button in @(
        @{ Id = 'windows-hero-download-action'; Status = 'windows-hero-status' },
        @{ Id = 'windows-download-action'; Status = 'windows-card-status' }
    )) {
        $buttonStart = '<button class="button button-secondary" id="' + $button.Id +
            '" type="button" disabled aria-describedby="' + $button.Status + '">'
        $buttonIndex = $html.IndexOf($buttonStart, [StringComparison]::Ordinal)
        if ($buttonIndex -lt 0) {
            throw "Inactive Windows download button is missing: $relativePath / $($button.Id)"
        }

        $activeStart = '<a class="button button-secondary" id="' + $button.Id +
            '" href="' + $installerUrl + '" aria-describedby="' + $button.Status + '">'
        $html = $html.Remove($buttonIndex, $buttonStart.Length).Insert($buttonIndex, $activeStart)
        $buttonEndIndex = $html.IndexOf('</button>', $buttonIndex, [StringComparison]::Ordinal)
        if ($buttonEndIndex -lt 0) {
            throw "Windows download button closing tag is missing: $relativePath / $($button.Id)"
        }
        $html = $html.Remove($buttonEndIndex, '</button>'.Length).Insert($buttonEndIndex, '</a>')
    }
    [IO.File]::WriteAllText($path, $html, $utf8NoBom)
}

Write-Host 'WindowsPagesReleasePrepared=true'
Write-Host "Version=$version"
Write-Host "InstallerUrl=$installerUrl"
Write-Host "SHA256=$hash"
