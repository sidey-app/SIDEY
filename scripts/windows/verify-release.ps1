[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$CandidateSetup
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$candidate = (Resolve-Path $CandidateSetup).Path
$setupName = "SIDEY-Windows-x64-v$Version-Setup.exe"
if ([System.IO.Path]::GetFileName($candidate) -ne $setupName) {
    throw "후보 파일 이름이 공개 계약과 다름: $setupName"
}

$tag = "v$Version"
$releaseRoot = "https://github.com/sidey-app/SIDEY/releases/download/$tag"
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "sidey-windows-release-$([Guid]::NewGuid().ToString('N'))"
[System.IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
try {
    $downloadedSetup = Join-Path $temporaryRoot $setupName
    $downloadedChecksum = "$downloadedSetup.sha256"
    Invoke-WebRequest -Uri "$releaseRoot/$setupName" -OutFile $downloadedSetup
    Invoke-WebRequest -Uri "$releaseRoot/$setupName.sha256" -OutFile $downloadedChecksum

    $checksumLine = (Get-Content -Path $downloadedChecksum -Raw).Trim()
    $checksumMatch = [regex]::Match(
        $checksumLine,
        "^(?<hash>[0-9a-fA-F]{64}) [ *]$([regex]::Escape($setupName))$")
    if (-not $checksumMatch.Success) {
        throw "Release SHA-256 파일 형식 또는 대상 파일명이 올바르지 않음"
    }

    $declaredHash = $checksumMatch.Groups['hash'].Value.ToLowerInvariant()
    $downloadedHash = (Get-FileHash $downloadedSetup -Algorithm SHA256).Hash.ToLowerInvariant()
    $candidateHash = (Get-FileHash $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($downloadedHash -ne $declaredHash) {
        throw "Release에서 다시 받은 Setup.exe와 게시된 SHA-256이 다름"
    }
    if ($downloadedHash -ne $candidateHash) {
        throw "Release Setup.exe가 CI에서 검증한 로컬 후보와 다름"
    }

    Write-Host "ReleaseVerified=true"
    Write-Host "Version=$Version"
    Write-Host "SHA256=$downloadedHash"
    Write-Host "이 확인 뒤에만 Windows CTA와 update manifest를 별도 변경하세요."
}
finally {
    if (Test-Path $temporaryRoot -PathType Container) {
        Remove-Item -Path $temporaryRoot -Recurse -Force
    }
}
