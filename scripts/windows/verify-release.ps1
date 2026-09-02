[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$CandidateMsi
)

$ErrorActionPreference = 'Stop'
$candidate = (Resolve-Path -LiteralPath $CandidateMsi).Path
$msiName = "SIDEY-Windows-x64-v$Version.msi"
if ([IO.Path]::GetFileName($candidate) -ne $msiName) {
    throw "후보 파일 이름이 공개 계약과 다름: $msiName"
}

$tag = "windows-v$Version"
$releaseUrl = "https://github.com/sidey-app/SIDEY/releases/download/$tag/$msiName"
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "sidey-windows-release-$([Guid]::NewGuid().ToString('N'))"
[IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
try {
    $downloadedMsi = Join-Path $temporaryRoot $msiName
    Invoke-WebRequest -Uri $releaseUrl -OutFile $downloadedMsi

    $downloadedHash = (Get-FileHash -LiteralPath $downloadedMsi -Algorithm SHA256).Hash.ToLowerInvariant()
    $candidateHash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($downloadedHash -ne $candidateHash) {
        throw 'Release MSI가 CI에서 검증한 로컬 후보와 다름'
    }

    Write-Host 'ReleaseVerified=true'
    Write-Host "Version=$Version"
    Write-Host "SHA256=$downloadedHash"
    Write-Host '이 확인 뒤에만 Windows CTA와 update manifest를 별도 변경하세요.'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
