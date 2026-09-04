[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDir,

    [Parameter(Mandatory = $true)]
    [string]$OutDir,

    [string]$Version = '1.0.5',

    [string]$MakensisPath
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$resolvedPublishDir = (Resolve-Path -LiteralPath $PublishDir).Path
$resolvedOutDir = [System.IO.Path]::GetFullPath($OutDir)
$executable = Join-Path $resolvedPublishDir 'SIDEY.exe'
$uninstaller = Join-Path $resolvedPublishDir 'Uninstall.exe'
$runtimeDir = Join-Path $resolvedPublishDir 'Runtime'
$hostExecutable = Join-Path $runtimeDir 'SIDEY.Host.exe'
$legacyExecutable = Join-Path $resolvedPublishDir 'Sidey.App.exe'
$setupScript = Join-Path $repositoryRoot 'windows/installer/Sidey.Setup/Sidey.Setup.nsi'

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

if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "게시 폴더에 SIDEY.exe가 없음: $resolvedPublishDir"
}
if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) {
    throw "Published Uninstall.exe is missing: $resolvedPublishDir"
}
if (-not (Test-Path -LiteralPath $hostExecutable -PathType Leaf)) {
    throw "게시 폴더에 Runtime/SIDEY.Host.exe가 없음: $resolvedPublishDir"
}
if (Test-Path -LiteralPath $legacyExecutable -PathType Leaf) {
    throw '게시 진입점 이름이 아직 Sidey.App.exe임. SIDEY.exe 하나로 통일해야 함.'
}

$deployableFiles = @(Get-ChildItem -LiteralPath $resolvedPublishDir -Recurse -File |
    Where-Object { $_.Extension -ne '.pdb' })
$characterAssetRoot = Join-Path $resolvedPublishDir 'Assets/Character'
$throwableAssetRoot = Join-Path $resolvedPublishDir 'Assets/Throwable'
$iconRoot = Join-Path $resolvedPublishDir 'Assets/Icons'
$languageRoot = Join-Path $resolvedPublishDir 'Langs'
$requiredSideyBinaries = @(
    $executable,
    $uninstaller,
    $hostExecutable,
    (Join-Path $runtimeDir 'SIDEY.Host.dll'),
    (Join-Path $runtimeDir 'Sidey.Core.dll'),
    (Join-Path $runtimeDir 'Sidey.Infrastructure.dll'),
    (Join-Path $runtimeDir 'Sidey.Overlay.dll'),
    (Join-Path $runtimeDir 'Sidey.Platform.Windows.dll'),
    (Join-Path $runtimeDir 'Sidey.Presentation.dll')
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
$unexpectedRootItems = @(Get-ChildItem -LiteralPath $resolvedPublishDir -Force |
    Where-Object { -not $allowedRootNames.Contains($_.Name) })
if ($unexpectedRootItems.Count -gt 0) {
    throw "Unexpected item at the publish root: $($unexpectedRootItems.Name -join ', ')"
}
foreach ($directory in @($characterAssetRoot, $throwableAssetRoot, $iconRoot, $languageRoot)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Required publish directory is missing: $directory"
    }
}

$sourceIconRoot = Join-Path $repositoryRoot 'windows/src/Sidey.App/Assets/Icons'
$sourceIconNames = @(Get-ChildItem -LiteralPath $sourceIconRoot -File |
    Select-Object -ExpandProperty Name |
    Sort-Object)
$publishedIconNames = @(Get-ChildItem -LiteralPath $iconRoot -File |
    Select-Object -ExpandProperty Name |
    Sort-Object)
if ($sourceIconNames.Count -eq 0 -or
    @(Compare-Object $sourceIconNames $publishedIconNames).Count -gt 0) {
    throw 'Published SIDEY icon variants do not match the source icon set.'
}

$legacyAssetDirectories = @(
    (Join-Path $resolvedPublishDir 'Assets/Characters'),
    (Join-Path $resolvedPublishDir 'Assets/CharacterThrow')
)
$presentLegacyAssetDirectories = @($legacyAssetDirectories | Where-Object {
    Test-Path -LiteralPath $_ -PathType Container
})
if ($presentLegacyAssetDirectories.Count -gt 0) {
    throw "Legacy character asset directories remain in the publish output: $($presentLegacyAssetDirectories -join ', ')"
}

$characterAssetFiles = @(Get-ChildItem -LiteralPath $characterAssetRoot -Recurse -File)
$manifests = @($characterAssetFiles | Where-Object { $_.Name -eq 'manifest.json' })
$sourceCharacterAssetRoot = Join-Path $repositoryRoot 'windows/src/Sidey.Overlay/Assets/Character'
$sourceManifestNames = @(Get-ChildItem -LiteralPath $sourceCharacterAssetRoot -Filter 'manifest.json' -Recurse -File |
    ForEach-Object { Get-SideyRelativePath $sourceCharacterAssetRoot $_.FullName } |
    Sort-Object)
$publishedManifestNames = @($manifests |
    ForEach-Object { Get-SideyRelativePath $characterAssetRoot $_.FullName } |
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
        $path = Join-Path $manifest.Directory.FullName $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "캐릭터 외부 에셋이 누락됨: $characterId/$name"
        }
        [void]$expectedAssets.Add([System.IO.Path]::GetFullPath($path))
    }
}
$unexpectedCharacterAssets = @($characterAssetFiles | Where-Object {
    -not $expectedAssets.Contains($_.FullName)
})
if ($unexpectedCharacterAssets.Count -gt 0 -or
    $characterAssetFiles.Count -ne $expectedAssets.Count) {
    throw '캐릭터 외부 에셋에는 base/throw_hit PNG·BGRA와 manifest 세트만 둘 수 있음'
}

$sourceThrowableAssetRoot = Join-Path $repositoryRoot 'windows/src/Sidey.Overlay/Assets/Throwable'
$sourceThrowableFiles = @(Get-ChildItem -LiteralPath $sourceThrowableAssetRoot -Recurse -File |
    ForEach-Object { Get-SideyRelativePath $sourceThrowableAssetRoot $_.FullName } |
    Sort-Object)
$publishedThrowableFiles = @(Get-ChildItem -LiteralPath $throwableAssetRoot -Recurse -File |
    ForEach-Object { Get-SideyRelativePath $throwableAssetRoot $_.FullName } |
    Sort-Object)
if ($sourceThrowableFiles.Count -eq 0 -or
    @(Compare-Object $sourceThrowableFiles $publishedThrowableFiles).Count -gt 0) {
    throw '소스와 게시 폴더의 투척물 에셋 목록이 일치하지 않음'
}
foreach ($throwableDirectory in @(Get-ChildItem -LiteralPath $throwableAssetRoot -Directory)) {
    $fileNames = @(Get-ChildItem -LiteralPath $throwableDirectory.FullName -File |
        Select-Object -ExpandProperty Name |
        Sort-Object)
    if (@(Compare-Object @('sprite.bgra', 'sprite.png') $fileNames).Count -gt 0) {
        throw "투척물 외부 에셋에는 sprite PNG·BGRA 세트만 둘 수 있음: $($throwableDirectory.FullName)"
    }
}

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Windows 정식 버전은 숫자 세 부분이어야 함: $Version"
}
$publishedVersionInfo = (Get-Item -LiteralPath $hostExecutable).VersionInfo
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

[IO.Directory]::CreateDirectory($resolvedOutDir) | Out-Null
$internalDir = Join-Path $resolvedOutDir 'internal/setup-build'
[IO.Directory]::CreateDirectory($internalDir) | Out-Null
$termsSource = Join-Path $repositoryRoot 'website/terms.html'
$termsGenerator = Join-Path $repositoryRoot 'scripts/windows/generate-installer-terms.ps1'
$termsLicenseFile = Join-Path $internalDir 'SideyTerms.txt'
& $termsGenerator -SourceHtml $termsSource -OutputPath $termsLicenseFile
if (-not (Test-Path -LiteralPath $termsLicenseFile -PathType Leaf)) {
    throw 'SIDEY installer terms file was not generated.'
}
$termsBytes = [IO.File]::ReadAllBytes($termsLicenseFile)
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
$makensisVersionText = (& $resolvedMakensisPath /VERSION | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or
    $makensisVersionText -notmatch '^v?(?<version>\d+\.\d+(?:\.\d+)?)$') {
    throw "Unable to read the NSIS compiler version: $makensisVersionText"
}
$makensisVersion = [Version]::Parse($Matches.version)
if ($makensisVersion -lt [Version]'3.12') {
    throw "NSIS 3.12 or newer is required. Found $makensisVersion."
}

function ConvertTo-NsisLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)

    return $Value.Replace('$', '$$').Replace('"', '$\"')
}

$payloadFiles = @($deployableFiles | Where-Object {
    $_.FullName -ne $uninstaller
})
$installInclude = Join-Path $internalDir 'SideyPayloadInstall.nsh'
$uninstallInclude = Join-Path $internalDir 'SideyPayloadUninstall.nsh'
$installLines = [Collections.Generic.List[string]]::new()
$uninstallLines = [Collections.Generic.List[string]]::new()
$payloadDirectories = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)

foreach ($file in $payloadFiles) {
    $relativePath = Get-SideyRelativePath $resolvedPublishDir $file.FullName
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

$installLines | Set-Content -LiteralPath $installInclude -Encoding utf8
$uninstallLines | Set-Content -LiteralPath $uninstallInclude -Encoding utf8

& $resolvedMakensisPath `
    '/INPUTCHARSET' 'UTF8' `
    "/DAPP_VERSION=$Version" `
    "/DAPP_FILE_VERSION=$Version.0" `
    "/DOUTPUT_DIR=$internalDir" `
    "/DPUBLISH_DIR=$resolvedPublishDir" `
    "/DPAYLOAD_INSTALL_INCLUDE=$installInclude" `
    "/DPAYLOAD_UNINSTALL_INCLUDE=$uninstallInclude" `
    "/DTERMS_LICENSE_FILE=$termsLicenseFile" `
    $setupScript
if ($LASTEXITCODE -ne 0) {
    throw 'SIDEY Setup EXE build failed.'
}

$builtSetupFiles = @(Get-ChildItem -LiteralPath $internalDir -Filter '*.exe' -File)
if ($builtSetupFiles.Count -ne 1) {
    throw 'NSIS must produce exactly one Setup EXE.'
}

$setupName = "SIDEY-Windows-x64-v${Version}-Setup.exe"
$setupPath = Join-Path $resolvedOutDir $setupName
Copy-Item -LiteralPath $builtSetupFiles[0].FullName -Destination $setupPath -Force
$hash = (Get-FileHash -LiteralPath $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
$publishBytes = ($deployableFiles | Measure-Object -Property Length -Sum).Sum

Write-Host "PublishLayout=structured self-contained; Files=$($deployableFiles.Count); Bytes=$publishBytes"
Write-Host "NSIS=$makensisVersion"
Write-Host "Created public Setup EXE $setupPath"
Write-Host "SHA256=$hash"
