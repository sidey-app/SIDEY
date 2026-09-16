#requires -Version 5.1

[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$AssetsDirectory)

& (Join-Path $PSScriptRoot 'tests/Test-ImpactAudioAssets.ps1') @PSBoundParameters
