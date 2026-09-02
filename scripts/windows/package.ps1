[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDir,

    [Parameter(Mandatory = $true)]
    [string]$OutDir,

    [string]$Version = '0.3.0-alpha.7',

    [string]$BundleVersion = '0.3.0.7',

    [switch]$SuppressInstallerValidation
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$resolvedPublishDir = (Resolve-Path $PublishDir).Path
$resolvedOutDir = [System.IO.Path]::GetFullPath($OutDir)
$executable = Join-Path $resolvedPublishDir 'SIDEY.exe'
$runtimeDir = Join-Path $resolvedPublishDir 'Runtime'
$hostExecutable = Join-Path $runtimeDir 'SIDEY.Host.exe'
$legacyExecutable = Join-Path $resolvedPublishDir 'Sidey.App.exe'
$msiProject = Join-Path $repositoryRoot 'windows/installer/Sidey.Msi/Sidey.Msi.wixproj'
$bundleProject = Join-Path $repositoryRoot 'windows/installer/Sidey.Bundle/Sidey.Bundle.wixproj'
$signingScript = Join-Path $repositoryRoot 'scripts/windows/sign-self-signed.ps1'

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

if (-not (Test-Path $executable -PathType Leaf)) {
    throw "게시 폴더에 SIDEY.exe가 없음: $resolvedPublishDir"
}
if (Test-Path $legacyExecutable -PathType Leaf) {
    throw "게시 진입점 이름이 아직 Sidey.App.exe임. SIDEY.exe 하나로 통일해야 함."
}

$deployableFiles = @(Get-ChildItem -Path $resolvedPublishDir -Recurse -File |
    Where-Object { $_.Extension -ne '.pdb' })
$assetRoot = Join-Path $resolvedPublishDir 'Assets/Characters'
$iconRoot = Join-Path $resolvedPublishDir 'Assets/Icons'
$languageRoot = Join-Path $resolvedPublishDir 'Langs'
$sideyBinaries = @(
    $executable,
    $hostExecutable,
    (Join-Path $runtimeDir 'SIDEY.Host.dll'),
    (Join-Path $runtimeDir 'Sidey.Core.dll'),
    (Join-Path $runtimeDir 'Sidey.Infrastructure.dll'),
    (Join-Path $runtimeDir 'Sidey.Overlay.dll'),
    (Join-Path $runtimeDir 'Sidey.Platform.Windows.dll'),
    (Join-Path $runtimeDir 'Sidey.Presentation.dll')
)
$missingSideyBinaries = @($sideyBinaries | Where-Object {
    -not (Test-Path -LiteralPath $_ -PathType Leaf)
})
if ($missingSideyBinaries.Count -gt 0) {
    $missingNames = @($missingSideyBinaries | ForEach-Object {
        Split-Path -Leaf $_
    })
    throw "Required SIDEY binaries are missing from the multi-file publish: $($missingNames -join ', ')"
}
$allowedRootNames = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($name in @(
    'SIDEY.exe',
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
if (-not (Test-Path -LiteralPath $languageRoot -PathType Container)) {
    throw "SIDEY language directory is missing: $languageRoot"
}
if (-not (Test-Path $assetRoot -PathType Container)) {
    throw "외부 캐릭터 에셋 폴더가 없음: $assetRoot"
}

if (-not (Test-Path $iconRoot -PathType Container)) {
    throw "SIDEY icon asset directory is missing: $iconRoot"
}

$sourceIconRoot = Join-Path $repositoryRoot 'windows/src/Sidey.App/Assets/Icons'
$sourceIconNames = @(Get-ChildItem -Path $sourceIconRoot -File |
    Select-Object -ExpandProperty Name |
    Sort-Object)
$publishedIconNames = @(Get-ChildItem -Path $iconRoot -File |
    Select-Object -ExpandProperty Name |
    Sort-Object)
$iconDifference = @(Compare-Object `
    -ReferenceObject $sourceIconNames `
    -DifferenceObject $publishedIconNames)
if ($sourceIconNames.Count -eq 0 -or $iconDifference.Count -gt 0) {
    throw "Published SIDEY icon variants do not match the source icon set."
}

$assetFiles = @(Get-ChildItem -Path $assetRoot -Recurse -File)
$manifests = @($assetFiles | Where-Object { $_.Name -eq 'manifest.json' })
$sourceAssetRoot = Join-Path $repositoryRoot 'windows/src/Sidey.Overlay/Assets/Characters'
$sourceManifestNames = @(Get-ChildItem -Path $sourceAssetRoot -Filter 'manifest.json' -Recurse -File |
    ForEach-Object { Get-SideyRelativePath $sourceAssetRoot $_.FullName } |
    Sort-Object)
$publishedManifestNames = @($manifests |
    ForEach-Object { Get-SideyRelativePath $assetRoot $_.FullName } |
    Sort-Object)
$manifestDifference = @(Compare-Object `
    -ReferenceObject $sourceManifestNames `
    -DifferenceObject $publishedManifestNames)
if ($sourceManifestNames.Count -eq 0 -or $manifestDifference.Count -gt 0) {
    throw "소스와 게시 폴더의 캐릭터 manifest 목록이 일치하지 않음"
}
$expectedAssets = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase)
foreach ($manifest in $manifests) {
    $metadata = Get-Content -Path $manifest.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $characterId = [string]$metadata.character_id
    if ([string]::IsNullOrWhiteSpace($characterId) `
        -or $manifest.Directory.Name -ne $characterId) {
        throw "캐릭터 폴더 이름과 character_id가 일치하지 않음: $($manifest.FullName)"
    }
    foreach ($name in @('sprite.png', 'frames.bgra', 'manifest.json')) {
        $path = Join-Path $manifest.Directory.FullName $name
        if (-not (Test-Path $path -PathType Leaf)) {
            throw "캐릭터 외부 에셋이 누락됨: $characterId/$name"
        }
        [void]$expectedAssets.Add([System.IO.Path]::GetFullPath($path))
    }
}
$unexpectedAssets = @($assetFiles | Where-Object {
    -not $expectedAssets.Contains($_.FullName)
})
if ($unexpectedAssets.Count -gt 0 -or $assetFiles.Count -ne $expectedAssets.Count) {
    throw "캐릭터 외부 에셋에는 PNG/BGRA/manifest 세트만 둘 수 있음"
}
$publishBytes = ($deployableFiles | Measure-Object -Property Length -Sum).Sum
Write-Host "PublishLayout=structured self-contained; Files=$($deployableFiles.Count); Bytes=$publishBytes; Host=Runtime/SIDEY.Host.exe; CharacterFiles=$($assetFiles.Count)"

$versionMatch = [regex]::Match($Version, '^(?<product>\d+\.\d+\.\d+)(?:-[0-9A-Za-z.-]+)?$')
if (-not $versionMatch.Success) {
    throw "표시 버전 형식이 올바르지 않음: $Version"
}
if ($BundleVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    throw "Burn bundle 버전은 숫자 4부 형식이어야 함: $BundleVersion"
}
try {
    [void][Version]$BundleVersion
}
catch {
    throw "Burn bundle 버전은 숫자 4부 형식이어야 함: $BundleVersion"
}

$displayCore = [Version]$versionMatch.Groups['product'].Value
$publishedVersionInfo = (Get-Item $hostExecutable).VersionInfo
$publishedProductVersion = $publishedVersionInfo.ProductVersion
if (-not $publishedProductVersion.StartsWith(
    "$Version+",
    [System.StringComparison]::OrdinalIgnoreCase) `
    -and -not [string]::Equals(
        $publishedProductVersion,
        $Version,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Published SIDEY.Host.exe version does not match the package version: $publishedProductVersion / $Version"
}
$burnVersion = [Version]$BundleVersion
if (-not [string]::Equals(
    $publishedVersionInfo.FileVersion,
    $BundleVersion,
    [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Published SIDEY.Host.exe file version does not match the bundle version: $($publishedVersionInfo.FileVersion) / $BundleVersion"
}
if ($burnVersion.Major -ne $displayCore.Major `
    -or $burnVersion.Minor -ne $displayCore.Minor `
    -or $burnVersion.Build -ne $displayCore.Build) {
    throw "Burn bundle 버전의 앞 세 자리는 표시 버전과 같아야 함: $BundleVersion / $Version"
}
if ($burnVersion.Revision -lt 1 -or $burnVersion.Revision -gt 999) {
    throw "Burn bundle revision은 alpha 순번 1~998 또는 stable 예약값 999여야 함: $BundleVersion"
}
$msiBuild = ($burnVersion.Build * 1000) + $burnVersion.Revision
if ($msiBuild -gt 65535) {
    throw "MSI build 필드가 65535를 초과함: $msiBuild"
}
$productVersion = "$($burnVersion.Major).$($burnVersion.Minor).$msiBuild"
[System.IO.Directory]::CreateDirectory($resolvedOutDir) | Out-Null
$certificatePath = Join-Path $resolvedOutDir 'SIDEY-SelfSigned-CodeSigning.cer'
$internalDir = Join-Path $resolvedOutDir 'internal'
$temporaryPfxPath = Join-Path $internalDir 'SIDEY-signing-temporary.pfx'
$temporaryPfxPassword = [Guid]::NewGuid().ToString('N')
if (Test-Path -LiteralPath $temporaryPfxPath -PathType Leaf) {
    Remove-Item -LiteralPath $temporaryPfxPath -Force
}
try {
& $signingScript `
    -Path $sideyBinaries `
    -CertificateOutPath $certificatePath `
    -CertificatePfxPath $temporaryPfxPath `
    -CertificatePassword $temporaryPfxPassword
$msiBuildDir = Join-Path $internalDir 'msi-build'
$bundleBuildDir = Join-Path $internalDir 'bundle-build'
[System.IO.Directory]::CreateDirectory($msiBuildDir) | Out-Null
[System.IO.Directory]::CreateDirectory($bundleBuildDir) | Out-Null

dotnet build $msiProject `
    --configuration Release `
    --no-restore `
    --no-incremental `
    --output $msiBuildDir `
    "-p:PublishDir=$resolvedPublishDir" `
    "-p:ProductVersion=$productVersion" `
    "-p:DisplayVersion=$Version" `
    "-p:SuppressValidation=$($SuppressInstallerValidation.IsPresent.ToString().ToLowerInvariant())"
if ($LASTEXITCODE -ne 0) {
    throw "SIDEY 내부 MSI 빌드 실패"
}

$msiFiles = @(Get-ChildItem -Path $msiBuildDir -Filter '*.msi' -File)
if ($msiFiles.Count -ne 1) {
    throw "WiX 빌드에서 내부 MSI가 정확히 하나 생성되지 않음"
}
$msi = $msiFiles[0]
& $signingScript `
    -Path $msi.FullName `
    -CertificatePfxPath $temporaryPfxPath `
    -CertificatePassword $temporaryPfxPassword

dotnet build $bundleProject `
    --configuration Release `
    --no-restore `
    --no-incremental `
    --output $bundleBuildDir `
    "-p:MsiPath=$($msi.FullName)" `
    "-p:BundleVersion=$BundleVersion" `
    "-p:DisplayVersion=$Version"
if ($LASTEXITCODE -ne 0) {
    throw "SIDEY Burn Setup 빌드 실패"
}

$setupName = "SIDEY-Windows-x64-v$Version-Setup.exe"
$setupPath = Join-Path $resolvedOutDir $setupName
$builtSetups = @(Get-ChildItem -Path $bundleBuildDir -Filter '*.exe' -File)
if ($builtSetups.Count -ne 1) {
    throw "WiX Burn 빌드에서 Setup.exe가 정확히 하나 생성되지 않음"
}
$builtSetup = $builtSetups[0]
Copy-Item -Path $builtSetup.FullName -Destination $setupPath -Force
& $signingScript `
    -Path $setupPath `
    -CertificatePfxPath $temporaryPfxPath `
    -CertificatePassword $temporaryPfxPassword

$testMsiName = "SIDEY-Windows-x64-v$Version-Test.msi"
$testMsiPath = Join-Path $resolvedOutDir $testMsiName
Copy-Item -Path $msi.FullName -Destination $testMsiPath -Force
if ((Get-Item $setupPath).Length -le (Get-Item $testMsiPath).Length) {
    throw "Burn Setup.exe가 내부 MSI보다 작음. 오프라인 payload 내장을 확인해야 함."
}

$hashPath = "$setupPath.sha256"
$hash = (Get-FileHash -Path $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText(
    $hashPath,
    "$hash *$setupName$([Environment]::NewLine)",
    [System.Text.UTF8Encoding]::new($false))

$testMsiHashPath = "$testMsiPath.sha256"
$testMsiHash = (Get-FileHash -Path $testMsiPath -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText(
    $testMsiHashPath,
    "$testMsiHash *$testMsiName$([Environment]::NewLine)",
    [System.Text.UTF8Encoding]::new($false))

Write-Host "Created public candidate $setupPath"
Write-Host "Created checksum $hashPath"
Write-Host "Created test MSI $testMsiPath"
Write-Host "Created test MSI checksum $testMsiHashPath"
}
finally {
    if (Test-Path -LiteralPath $temporaryPfxPath -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryPfxPath -Force
    }
}
