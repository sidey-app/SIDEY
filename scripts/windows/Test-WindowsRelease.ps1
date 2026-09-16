#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$CandidateSetupPath
)

& (Join-Path $PSScriptRoot 'tests/Test-WindowsRelease.ps1') @PSBoundParameters
