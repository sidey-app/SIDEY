[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WebsiteDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [Parameter(Mandatory = $true)]
    [string]$MacOSReleaseManifest,

    [Parameter(Mandatory = $true)]
    [string]$MacOSReleaseDmg,

    [Parameter(Mandatory = $true)]
    [string]$WindowsReleaseManifest,

    [Parameter(Mandatory = $true)]
    [string]$WindowsReleaseInstaller
)

$ErrorActionPreference = 'Stop'
$resolvedWebsiteDir = (Resolve-Path -LiteralPath $WebsiteDir).Path
$resolvedMacOSReleaseManifest = (Resolve-Path -LiteralPath $MacOSReleaseManifest).Path
$resolvedMacOSReleaseDmg = (Resolve-Path -LiteralPath $MacOSReleaseDmg).Path
$resolvedWindowsReleaseManifest = (Resolve-Path -LiteralPath $WindowsReleaseManifest).Path
$resolvedWindowsReleaseInstaller = (Resolve-Path -LiteralPath $WindowsReleaseInstaller).Path
$resolvedOutputDir = [IO.Path]::GetFullPath($OutputDir)

$macOSManifest = Get-Content -LiteralPath $resolvedMacOSReleaseManifest -Raw -Encoding UTF8 |
    ConvertFrom-Json
$windowsManifest = Get-Content -LiteralPath $resolvedWindowsReleaseManifest -Raw -Encoding UTF8 |
    ConvertFrom-Json

if ($macOSManifest.schema -ne 1 -or
    $macOSManifest.platform -ne 'macos' -or
    $macOSManifest.channel -ne 'production' -or
    [string]$macOSManifest.version -notmatch '^\d+\.\d+\.\d+$') {
    throw 'release/macos.json must describe a stable production macOS release.'
}
if ($windowsManifest.schema -ne 1 -or
    $windowsManifest.platform -ne 'windows' -or
    $windowsManifest.channel -ne 'production' -or
    [string]$windowsManifest.version -notmatch '^\d+\.\d+\.\d+$') {
    throw 'release/windows.json must describe a stable production Windows release.'
}

$macOSVersion = [string]$macOSManifest.version
$macOSTag = "v$macOSVersion"
$macOSDmgName = "SIDEY-macOS-arm64-v${macOSVersion}.dmg"
$macOSDmgUrl = "https://github.com/sidey-app/SIDEY/releases/download/$macOSTag/$macOSDmgName"
$windowsVersion = [string]$windowsManifest.version
$windowsTag = "windows-v$windowsVersion"
$windowsInstallerName = "SIDEY-Windows-x64-v${windowsVersion}-Setup.exe"
$windowsInstallerUrl = "https://github.com/sidey-app/SIDEY/releases/download/$windowsTag/$windowsInstallerName"

if ([IO.Path]::GetFileName($resolvedMacOSReleaseDmg) -cne $macOSDmgName) {
    throw "macOS release asset filename does not match the public contract: $macOSDmgName"
}
if ([IO.Path]::GetFileName($resolvedWindowsReleaseInstaller) -cne $windowsInstallerName) {
    throw "Windows release installer filename does not match the public contract: $windowsInstallerName"
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

$macOSHash = (Get-FileHash -LiteralPath $resolvedMacOSReleaseDmg -Algorithm SHA256).Hash.ToLowerInvariant()
$windowsHash = (Get-FileHash -LiteralPath $resolvedWindowsReleaseInstaller -Algorithm SHA256).Hash.ToLowerInvariant()
$publishedWindowsManifest = [ordered]@{
    channel = 'production'
    version = $windowsVersion
    tag = $windowsTag
    installer_url = $windowsInstallerUrl
    sha256 = $windowsHash
}
$manifestJson = $publishedWindowsManifest | ConvertTo-Json
$utf8NoBom = [Text.UTF8Encoding]::new($false)
foreach ($relativePath in @('windows-latest.json', 'windows/update.json')) {
    $path = Join-Path $resolvedOutputDir $relativePath
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
    [IO.File]::WriteAllText($path, "$manifestJson`n", $utf8NoBom)
}

foreach ($relativePath in @('ko/index.html', 'en/index.html', 'ja/index.html')) {
    $path = Join-Path $resolvedOutputDir $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Localized landing page is missing: $relativePath"
    }
    $html = [IO.File]::ReadAllText($path)
    $appStoreUrl = "https://apps.apple.com/kr/app/sidey/id6808528060?mt=12"
    $heroLinkPattern = '<a(?=[^>]*\bid="primary-download-action")' +
        '(?=[^>]*\bhref="' + [regex]::Escape($appStoreUrl) + '")' +
        '(?=[^>]*\bdata-macos-url="' + [regex]::Escape($appStoreUrl) + '")' +
        '(?=[^>]*\bdata-windows-url="' + [regex]::Escape($windowsInstallerUrl) + '")[^>]*>'
    if (-not [regex]::IsMatch($html, $heroLinkPattern)) {
        throw "Verified OS-aware download link is missing: $relativePath / primary-download-action"
    }

    foreach ($download in @(
        @{ Platform = 'macos'; Id = 'macos-download-action'; Url = $macOSDmgUrl },
        @{ Platform = 'windows'; Id = 'windows-download-action'; Url = $windowsInstallerUrl }
    )) {
        $linkPattern = '<a(?=[^>]*\bid="' + [regex]::Escape($download.Id) + '")' +
            '(?=[^>]*\bhref="' + [regex]::Escape($download.Url) + '")[^>]*>'
        if (-not [regex]::IsMatch($html, $linkPattern)) {
            throw "Verified $($download.Platform) download link is missing: $relativePath / $($download.Id)"
        }
    }

    foreach ($checksum in @(
        @{ Platform = 'macos'; Id = 'macos-download-sha256'; Hash = $macOSHash },
        @{ Platform = 'windows'; Id = 'windows-download-sha256'; Hash = $windowsHash }
    )) {
        $hashPattern = '(<code(?=[^>]*\bid="' + [regex]::Escape($checksum.Id) + '")' +
            '(?=[^>]*\bdata-release-platform="' + $checksum.Platform + '")[^>]*>)[^<]*(</code>)'
        if (-not [regex]::IsMatch($html, $hashPattern)) {
            throw "Release SHA-256 field is missing: $relativePath / $($checksum.Platform)"
        }
        $html = [regex]::Replace(
            $html,
            $hashPattern,
            { param($match) $match.Groups[1].Value + $checksum.Hash + $match.Groups[2].Value }
        )
    }
    [IO.File]::WriteAllText($path, $html, $utf8NoBom)
}

Write-Host 'ReleaseMetadataPrepared=true'
Write-Host "MacOSVersion=$macOSVersion"
Write-Host "MacOSSHA256=$macOSHash"
Write-Host "WindowsVersion=$windowsVersion"
Write-Host "WindowsSHA256=$windowsHash"
