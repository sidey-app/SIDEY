#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDirectory,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$MakensisPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Sidey.PowerShell.psm1') -Force
$repositoryRootPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$publishDirectoryPath = (Resolve-Path -LiteralPath $PublishDirectory).Path
$outputDirectoryPath = [System.IO.Path]::GetFullPath($OutputDirectory)
$launcherExecutablePath = Join-Path $publishDirectoryPath 'SIDEY.exe'
$uninstallerPath = Join-Path $publishDirectoryPath 'Uninstall.exe'
$runtimeDirectory = Join-Path $publishDirectoryPath 'Runtime'
$hostExecutablePath = Join-Path $runtimeDirectory 'SIDEY.Host.exe'
$legacyExecutablePath = Join-Path $publishDirectoryPath 'Sidey.App.exe'
$setupScriptPath = Join-Path $repositoryRootPath 'windows/installer/Sidey.Setup/Sidey.Setup.nsi'
& (Join-Path $PSScriptRoot 'Test-FrameworkDependentPublish.ps1') -PublishDirectory $publishDirectoryPath

function Get-SideyRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $basePathWithSeparator = [System.IO.Path]::GetFullPath($BasePath)
    $separator = [System.IO.Path]::DirectorySeparatorChar.ToString()
    if (-not $basePathWithSeparator.EndsWith(
        $separator,
        [System.StringComparison]::Ordinal)) {
        $basePathWithSeparator += $separator
    }

    $baseUri = [Uri]::new($basePathWithSeparator)
    $targetUri = [Uri]::new([System.IO.Path]::GetFullPath($TargetPath))
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    return [Uri]::UnescapeDataString($relativeUri.ToString()).Replace(
        '/',
        [System.IO.Path]::DirectorySeparatorChar)
}

if (-not (Test-Path -LiteralPath $launcherExecutablePath -PathType Leaf)) {
    throw "게시 폴더에 SIDEY.exe가 없음: $publishDirectoryPath"
}
if (-not (Test-Path -LiteralPath $uninstallerPath -PathType Leaf)) {
    throw "Published Uninstall.exe is missing: $publishDirectoryPath"
}
if (-not (Test-Path -LiteralPath $hostExecutablePath -PathType Leaf)) {
    throw "게시 폴더에 Runtime/SIDEY.Host.exe가 없음: $publishDirectoryPath"
}
if (Test-Path -LiteralPath $legacyExecutablePath -PathType Leaf) {
    throw '게시 진입점 이름이 아직 Sidey.App.exe임. SIDEY.exe 하나로 통일해야 함.'
}

$deployableFiles = @(Get-ChildItem -LiteralPath $publishDirectoryPath -Recurse -File |
    Where-Object { $_.Extension -ne '.pdb' })
$characterAssetDirectory = Join-Path $publishDirectoryPath 'Assets/Characters'
$throwableAssetDirectory = Join-Path $publishDirectoryPath 'Assets/Throwables'
$iconDirectory = Join-Path $publishDirectoryPath 'Assets/Icons'
$languageDirectory = Join-Path $publishDirectoryPath 'Langs'
$requiredSideyBinaries = @(
    $launcherExecutablePath,
    $uninstallerPath,
    $hostExecutablePath,
    (Join-Path $runtimeDirectory 'SIDEY.Host.dll'),
    (Join-Path $runtimeDirectory 'Sidey.Core.dll'),
    (Join-Path $runtimeDirectory 'Sidey.Infrastructure.dll'),
    (Join-Path $runtimeDirectory 'Sidey.Overlay.dll'),
    (Join-Path $runtimeDirectory 'Sidey.Platform.Windows.dll'),
    (Join-Path $runtimeDirectory 'Sidey.Presentation.dll')
)
$missingBinaries = @($requiredSideyBinaries | Where-Object {
    -not (Test-Path -LiteralPath $_ -PathType Leaf)
})
if ($missingBinaries.Count -gt 0) {
    throw "Required SIDEY binaries are missing: $($missingBinaries -join ', ')"
}

$allowedRootNames = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($name in @(
    'SIDEY.exe',
    'Uninstall.exe',
    'Assets',
    'Langs',
    'Runtime')) {
    [void]$allowedRootNames.Add($name)
}
$unexpectedRootItems = @(Get-ChildItem -LiteralPath $publishDirectoryPath -Force |
    Where-Object { -not $allowedRootNames.Contains($_.Name) })
if ($unexpectedRootItems.Count -gt 0) {
    throw "Unexpected item at the publish root: $($unexpectedRootItems.Name -join ', ')"
}
foreach ($directory in @($characterAssetDirectory, $throwableAssetDirectory, $iconDirectory, $languageDirectory)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Required publish directory is missing: $directory"
    }
}

$sourceIconDirectory = Join-Path $repositoryRootPath 'windows/src/Sidey.App/Assets/Icons'
$sourceIconNames = @(Get-ChildItem -LiteralPath $sourceIconDirectory -File |
    Select-Object -ExpandProperty Name |
    Sort-Object)
$publishedIconNames = @(Get-ChildItem -LiteralPath $iconDirectory -File |
    Select-Object -ExpandProperty Name |
    Sort-Object)
if ($sourceIconNames.Count -eq 0 -or
    @(Compare-Object $sourceIconNames $publishedIconNames).Count -gt 0) {
    throw 'Published SIDEY icon variants do not match the source icon set.'
}

$legacyAssetDirectories = @(
    (Join-Path $publishDirectoryPath 'Assets/Character'),
    (Join-Path $publishDirectoryPath 'Assets/Throwable'),
    (Join-Path $publishDirectoryPath 'Assets/CharacterThrow')
)
$presentLegacyAssetDirectories = @($legacyAssetDirectories | Where-Object {
    Test-Path -LiteralPath $_ -PathType Container
})
if ($presentLegacyAssetDirectories.Count -gt 0) {
    throw "Legacy character asset directories remain in the publish output: $($presentLegacyAssetDirectories -join ', ')"
}

$characterAssetFiles = @(Get-ChildItem -LiteralPath $characterAssetDirectory -Recurse -File)
$manifests = @($characterAssetFiles | Where-Object { $_.Name -eq 'manifest.json' })
$sourceCharacterAssetDirectory = Join-Path $repositoryRootPath 'windows/src/Sidey.Overlay/Assets/Characters'
$sourceManifestNames = @(Get-ChildItem -LiteralPath $sourceCharacterAssetDirectory -Filter 'manifest.json' -Recurse -File |
    ForEach-Object { Get-SideyRelativePath $sourceCharacterAssetDirectory $_.FullName } |
    Sort-Object)
$publishedManifestNames = @($manifests |
    ForEach-Object { Get-SideyRelativePath $characterAssetDirectory $_.FullName } |
    Sort-Object)
if ($sourceManifestNames.Count -eq 0 -or
    @(Compare-Object $sourceManifestNames $publishedManifestNames).Count -gt 0) {
    throw '소스와 게시 폴더의 캐릭터 manifest 목록이 일치하지 않음'
}

$expectedAssets = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($manifest in $manifests) {
    $metadata = Get-Content -LiteralPath $manifest.FullName -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $characterId = [string]$metadata.character_id
    if ([string]::IsNullOrWhiteSpace($characterId) -or
        $manifest.Directory.Name -ne $characterId) {
        throw "캐릭터 폴더 이름과 character_id가 일치하지 않음: $($manifest.FullName)"
    }
    foreach ($name in @('base.png', 'base.bgra', 'throw_hit.png', 'throw_hit.bgra', 'manifest.json')) {
        $requiredAssetPath = Join-Path $manifest.Directory.FullName $name
        if (-not (Test-Path -LiteralPath $requiredAssetPath -PathType Leaf)) {
            throw "캐릭터 외부 에셋이 누락됨: $characterId/$name"
        }
        [void]$expectedAssets.Add([System.IO.Path]::GetFullPath($requiredAssetPath))
    }
}
$unexpectedCharacterAssets = @($characterAssetFiles | Where-Object {
    -not $expectedAssets.Contains($_.FullName)
})
if ($unexpectedCharacterAssets.Count -gt 0 -or
    $characterAssetFiles.Count -ne $expectedAssets.Count) {
    throw '캐릭터 외부 에셋에는 base/throw_hit PNG·BGRA와 manifest 세트만 둘 수 있음'
}

$sourceThrowableAssetDirectory = Join-Path $repositoryRootPath 'windows/src/Sidey.Overlay/Assets/Throwables'
$sourceThrowableFiles = @(Get-ChildItem -LiteralPath $sourceThrowableAssetDirectory -Recurse -File |
    ForEach-Object { Get-SideyRelativePath $sourceThrowableAssetDirectory $_.FullName } |
    Sort-Object)
$publishedThrowableFiles = @(Get-ChildItem -LiteralPath $throwableAssetDirectory -Recurse -File |
    ForEach-Object { Get-SideyRelativePath $throwableAssetDirectory $_.FullName } |
    Sort-Object)
if ($sourceThrowableFiles.Count -eq 0 -or
    @(Compare-Object $sourceThrowableFiles $publishedThrowableFiles).Count -gt 0) {
    throw '소스와 게시 폴더의 투척물 에셋 목록이 일치하지 않음'
}
foreach ($throwableDirectory in @(Get-ChildItem -LiteralPath $throwableAssetDirectory -Directory)) {
    $fileNames = @(Get-ChildItem -LiteralPath $throwableDirectory.FullName -File |
        Select-Object -ExpandProperty Name |
        Sort-Object)
    $expectedFileNames = @('sprite.bgra', 'sprite.png')
    if ($throwableDirectory.Name -eq 'throwable_toy_cannon') {
        $expectedFileNames += @('emitter.bgra', 'emitter.png', 'preview.png')
    }
    $expectedFileNames = @($expectedFileNames | Sort-Object)
    if (@(Compare-Object $expectedFileNames $fileNames).Count -gt 0) {
        throw "투척물 외부 에셋 구성이 허용 목록과 다름: $($throwableDirectory.FullName)"
    }
}

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Windows 정식 버전은 숫자 세 부분이어야 함: $Version"
}
$publishedVersionInfo = (Get-Item -LiteralPath $hostExecutablePath).VersionInfo
if (-not $publishedVersionInfo.ProductVersion.StartsWith(
    $Version,
    [StringComparison]::OrdinalIgnoreCase)) {
    throw "Published SIDEY.Host.exe version does not match: $($publishedVersionInfo.ProductVersion) / $Version"
}
if (-not $publishedVersionInfo.FileVersion.StartsWith(
    "$Version.",
    [StringComparison]::OrdinalIgnoreCase)) {
    throw "Published SIDEY.Host.exe file version does not match: $($publishedVersionInfo.FileVersion) / $Version"
}

[IO.Directory]::CreateDirectory($outputDirectoryPath) | Out-Null
$installerBuildDirectory = Join-Path $outputDirectoryPath 'internal/setup-build'
[IO.Directory]::CreateDirectory($installerBuildDirectory) | Out-Null
$languageSelectorPath = Join-Path $installerBuildDirectory 'language/Sidey.SetupLanguage.exe'
$termsSourcePath = Join-Path $repositoryRootPath 'website/src/pages/ko/terms.md'
$termsGeneratorPath = Join-Path $PSScriptRoot 'New-InstallerTerms.ps1'
$termsLicenseFilePath = Join-Path $installerBuildDirectory 'SideyTerms.txt'
& $termsGeneratorPath -SourceMarkdownPath $termsSourcePath -OutputPath $termsLicenseFilePath
if (-not (Test-Path -LiteralPath $termsLicenseFilePath -PathType Leaf)) {
    throw 'SIDEY installer terms file was not generated.'
}
$termsBytes = [IO.File]::ReadAllBytes($termsLicenseFilePath)
if ($termsBytes.Length -lt 3 -or
    $termsBytes[0] -ne 0xEF -or
    $termsBytes[1] -ne 0xBB -or
    $termsBytes[2] -ne 0xBF) {
    throw 'SIDEY installer terms must be UTF-8 with BOM.'
}
$strictUtf8 = [Text.UTF8Encoding]::new($true, $true)
try {
    [void]$strictUtf8.GetString($termsBytes, 3, $termsBytes.Length - 3)
}
catch {
    throw 'SIDEY installer terms contain invalid UTF-8 bytes.'
}

$makensisCandidates = @()
if (-not [string]::IsNullOrWhiteSpace($MakensisPath)) {
    $makensisCandidates += $MakensisPath
}
$makensisCommand = Get-Command makensis.exe -ErrorAction SilentlyContinue
if ($null -ne $makensisCommand) {
    $makensisCandidates += $makensisCommand.Source
}
$programFilesX86 = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::ProgramFilesX86)
$programFiles = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::ProgramFiles)
$makensisCandidates += @(
    (Join-Path $programFilesX86 'NSIS\makensis.exe'),
    (Join-Path $programFiles 'NSIS\makensis.exe')
)
$resolvedMakensisPath = $makensisCandidates |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
    Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($resolvedMakensisPath)) {
    throw 'NSIS 3.12 or newer is required. Install NSIS.NSIS or pass -MakensisPath.'
}
$makensisVersionText = (Invoke-SideyNativeCommand `
    -FilePath $resolvedMakensisPath `
    -ArgumentList @('/VERSION') `
    -Description 'NSIS compiler version check' | Out-String).Trim()
if ($makensisVersionText -notmatch '^v?(?<version>\d+\.\d+(?:\.\d+)?)$') {
    throw "Unable to read the NSIS compiler version: $makensisVersionText"
}
$makensisVersion = [Version]::Parse($Matches.version)
if ($makensisVersion -lt [Version]'3.12') {
    throw "NSIS 3.12 or newer is required. Found $makensisVersion."
}
Invoke-SideyNativeCommand `
    -FilePath 'powershell.exe' `
    -ArgumentList @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $PSScriptRoot 'New-InstallerLanguageSelector.ps1'),
        '-OutputPath', $languageSelectorPath,
        '-NsisDirectory', (Split-Path -Parent $resolvedMakensisPath)
    ) `
    -Description 'Installer language selector build'

function ConvertTo-NsisLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)

    return $Value.Replace('$', '$$').Replace('"', '$\"')
}

$payloadFiles = @($deployableFiles | Where-Object {
    $_.FullName -ne $uninstallerPath
})
$installInclude = Join-Path $installerBuildDirectory 'SideyPayloadInstall.nsh'
$uninstallInclude = Join-Path $installerBuildDirectory 'SideyPayloadUninstall.nsh'
$installLines = [Collections.Generic.List[string]]::new()
$uninstallLines = [Collections.Generic.List[string]]::new()
$payloadDirectories = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)

foreach ($file in $payloadFiles) {
    $relativePath = Get-SideyRelativePath $publishDirectoryPath $file.FullName
    $relativeDirectory = Split-Path $relativePath -Parent
    $destination = '$INSTDIR'
    if (-not [string]::IsNullOrWhiteSpace($relativeDirectory)) {
        $destination += "\$(ConvertTo-NsisLiteral $relativeDirectory)"
        [void]$payloadDirectories.Add($relativeDirectory)
    }

    $installLines.Add("SetOutPath `"$destination`"")
    $installLines.Add("File `"$(ConvertTo-NsisLiteral $file.FullName)`"")
    $uninstallLines.Add(
        "Delete `"`$INSTDIR\$(ConvertTo-NsisLiteral $relativePath)`"")
}

foreach ($directory in @($payloadDirectories) |
    Sort-Object { ($_ -split '[\\/]').Count } -Descending) {
    $uninstallLines.Add(
        "RMDir `"`$INSTDIR\$(ConvertTo-NsisLiteral $directory)`"")
}

if (@($installLines + $uninstallLines | Where-Object {
    $_.IndexOf('$$INSTDIR', [StringComparison]::Ordinal) -ge 0
}).Count -gt 0) {
    throw 'Generated NSIS payload paths must expand $INSTDIR at runtime.'
}

$utf8WithoutBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllLines($installInclude, $installLines.ToArray(), $utf8WithoutBom)
[IO.File]::WriteAllLines($uninstallInclude, $uninstallLines.ToArray(), $utf8WithoutBom)

Invoke-SideyNativeCommand `
    -FilePath $resolvedMakensisPath `
    -ArgumentList @(
        '/INPUTCHARSET', 'UTF8',
        "/DAPP_VERSION=$Version",
        "/DAPP_FILE_VERSION=$Version.0",
        "/DOUTPUT_DIR=$installerBuildDirectory",
        "/DPUBLISH_DIR=$publishDirectoryPath",
        "/DPAYLOAD_INSTALL_INCLUDE=$installInclude",
        "/DPAYLOAD_UNINSTALL_INCLUDE=$uninstallInclude",
        "/DTERMS_LICENSE_FILE=$termsLicenseFilePath",
        "/DLANGUAGE_SELECTOR_EXE=$languageSelectorPath",
        $setupScriptPath
    ) `
    -Description 'SIDEY Setup EXE build'

$builtSetupFiles = @(Get-ChildItem -LiteralPath $installerBuildDirectory -Filter '*.exe' -File)
if ($builtSetupFiles.Count -ne 1) {
    throw 'NSIS must produce exactly one Setup EXE.'
}

$setupName = "SIDEY-Windows-x64-v${Version}-Setup.exe"
$setupFilePath = Join-Path $outputDirectoryPath $setupName
Copy-Item -LiteralPath $builtSetupFiles[0].FullName -Destination $setupFilePath -Force
$hash = (Get-FileHash -LiteralPath $setupFilePath -Algorithm SHA256).Hash.ToLowerInvariant()
$publishBytes = ($deployableFiles | Measure-Object -Property Length -Sum).Sum

Write-Host "PublishLayout=structured framework-dependent; Files=$($deployableFiles.Count); Bytes=$publishBytes"
Write-Host "NSIS=$makensisVersion"
Write-Host "Created public Setup EXE $setupFilePath"
Write-Host "SHA256=$hash"
