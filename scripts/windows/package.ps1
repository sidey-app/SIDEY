[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDir,

    [Parameter(Mandatory = $true)]
    [string]$OutDir,

    [string]$Version = '0.3.0-alpha.1'
)

$ErrorActionPreference = 'Stop'
$resolvedPublishDir = (Resolve-Path $PublishDir).Path
$resolvedOutDir = [System.IO.Path]::GetFullPath($OutDir)
$executable = Join-Path $resolvedPublishDir 'Sidey.App.exe'

if (-not (Test-Path $executable -PathType Leaf)) {
    throw "게시 폴더에 Sidey.App.exe가 없음: $resolvedPublishDir"
}

[System.IO.Directory]::CreateDirectory($resolvedOutDir) | Out-Null
$archiveName = "SIDEY-Windows-x64-$Version.zip"
$archivePath = Join-Path $resolvedOutDir $archiveName
$hashPath = "$archivePath.sha256"

Compress-Archive -Path (Join-Path $resolvedPublishDir '*') -DestinationPath $archivePath -CompressionLevel Optimal -Force
$hash = (Get-FileHash -Path $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Path $hashPath -Value "$hash *$archiveName" -Encoding utf8NoBOM

Write-Host "Created $archivePath"
Write-Host "Created $hashPath"
