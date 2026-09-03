[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDir,

    [Parameter(Mandatory = $true)]
    [string]$OutDir,

    [string]$Version = '1.0.5',

    [switch]$SuppressInstallerValidation
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
$msiProject = Join-Path $repositoryRoot 'windows/installer/Sidey.Msi/Sidey.Msi.wixproj'

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
    'SIDEY-Onboarding-Preview.cmd',
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
$internalDir = Join-Path $resolvedOutDir 'internal/msi-build'
[IO.Directory]::CreateDirectory($internalDir) | Out-Null

dotnet build $msiProject `
    --configuration Release `
    --no-restore `
    --no-incremental `
    --output $internalDir `
    "-p:PublishDir=$resolvedPublishDir" `
    "-p:ProductVersion=$Version" `
    "-p:DisplayVersion=$Version" `
    "-p:SuppressValidation=$($SuppressInstallerValidation.IsPresent.ToString().ToLowerInvariant())"
if ($LASTEXITCODE -ne 0) {
    throw 'SIDEY MSI 빌드 실패'
}

$builtMsiFiles = @(Get-ChildItem -LiteralPath $internalDir -Filter '*.msi' -File)
if ($builtMsiFiles.Count -ne 1) {
    throw 'WiX 빌드에서 MSI가 정확히 하나 생성되지 않음'
}

$msiName = "SIDEY-Windows-x64-v$Version.msi"
$msiPath = Join-Path $resolvedOutDir $msiName
Copy-Item -LiteralPath $builtMsiFiles[0].FullName -Destination $msiPath -Force
$hash = (Get-FileHash -LiteralPath $msiPath -Algorithm SHA256).Hash.ToLowerInvariant()
$publishBytes = ($deployableFiles | Measure-Object -Property Length -Sum).Sum

Write-Host "PublishLayout=structured self-contained; Files=$($deployableFiles.Count); Bytes=$publishBytes"
Write-Host "Created public MSI $msiPath"
Write-Host "SHA256=$hash"
