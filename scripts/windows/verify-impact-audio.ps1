[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$AssetsDir)

$ErrorActionPreference = 'Stop'
$assetsRoot = (Resolve-Path -LiteralPath $AssetsDir).Path
$audioRoot = Join-Path $assetsRoot 'Impacts'
if (Test-Path -LiteralPath (Join-Path $assetsRoot 'Audio/Impacts')) { throw 'Obsolete Audio/Impacts directory must not be deployed.' }
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $audioRoot 'manifest.json') | ConvertFrom-Json
if ($manifest.Count -ne 8 -or @($manifest.id | Select-Object -Unique).Count -ne 8) { throw 'Expected eight unique approved impact sounds.' }
foreach ($sound in $manifest) {
    if ($sound.id -notmatch '^[a-z_]+$' -or $sound.file -cne ($sound.id + '/' + $sound.id + '.wav')) { throw 'Invalid impact filename.' }
    $path = Join-Path $audioRoot $sound.file
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $sound.sha256) { throw "Impact hash mismatch: $($sound.id)" }
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 44 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -cne 'RIFF' -or [Text.Encoding]::ASCII.GetString($bytes, 8, 4) -cne 'WAVE') { throw 'Invalid WAV asset.' }
}
if (@(Get-ChildItem -LiteralPath $audioRoot -Filter '*.wav' -File -Recurse).Count -ne 8) { throw 'Unexpected impact audio files.' }
Write-Output 'Verified eight approved impact WAV files.'
