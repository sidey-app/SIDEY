[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDir,

    [Parameter(Mandatory = $true)]
    [string]$OutDir,

    [string]$Version = '0.3.0-alpha.1',

    [string]$BundleVersion = '0.3.0.1'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$resolvedPublishDir = (Resolve-Path $PublishDir).Path
$resolvedOutDir = [System.IO.Path]::GetFullPath($OutDir)
$executable = Join-Path $resolvedPublishDir 'SIDEY.exe'
$legacyExecutable = Join-Path $resolvedPublishDir 'Sidey.App.exe'
$msiProject = Join-Path $repositoryRoot 'windows/installer/Sidey.Msi/Sidey.Msi.wixproj'
$bundleProject = Join-Path $repositoryRoot 'windows/installer/Sidey.Bundle/Sidey.Bundle.wixproj'

if (-not (Test-Path $executable -PathType Leaf)) {
    throw "게시 폴더에 SIDEY.exe가 없음: $resolvedPublishDir"
}
if (Test-Path $legacyExecutable -PathType Leaf) {
    throw "게시 진입점 이름이 아직 Sidey.App.exe임. SIDEY.exe 하나로 통일해야 함."
}
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
$burnVersion = [Version]$BundleVersion
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
$internalDir = Join-Path $resolvedOutDir 'internal'
$msiBuildDir = Join-Path $internalDir 'msi-build'
$bundleBuildDir = Join-Path $internalDir 'bundle-build'
[System.IO.Directory]::CreateDirectory($msiBuildDir) | Out-Null
[System.IO.Directory]::CreateDirectory($bundleBuildDir) | Out-Null

dotnet build $msiProject `
    --configuration Release `
    --output $msiBuildDir `
    "-p:PublishDir=$resolvedPublishDir" `
    "-p:ProductVersion=$productVersion" `
    "-p:DisplayVersion=$Version"
if ($LASTEXITCODE -ne 0) {
    throw "SIDEY 내부 MSI 빌드 실패"
}

$msiFiles = @(Get-ChildItem -Path $msiBuildDir -Filter '*.msi' -File)
if ($msiFiles.Count -ne 1) {
    throw "WiX 빌드에서 내부 MSI가 정확히 하나 생성되지 않음"
}
$msi = $msiFiles[0]

dotnet build $bundleProject `
    --configuration Release `
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

$internalMsiPath = Join-Path $internalDir "SIDEY-Windows-x64-v$Version-internal.msi"
Copy-Item -Path $msi.FullName -Destination $internalMsiPath -Force
if ((Get-Item $setupPath).Length -le (Get-Item $internalMsiPath).Length) {
    throw "Burn Setup.exe가 내부 MSI보다 작음. 오프라인 payload 내장을 확인해야 함."
}

$hashPath = "$setupPath.sha256"
$hash = (Get-FileHash -Path $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Path $hashPath -Value "$hash *$setupName" -Encoding utf8NoBOM

Write-Host "Created public candidate $setupPath"
Write-Host "Created checksum $hashPath"
Write-Host "Retained CI-only MSI $internalMsiPath"
