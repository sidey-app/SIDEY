#requires -Version 5.1

[CmdletBinding()]
param([string]$Version)

& (Join-Path $PSScriptRoot 'tests/Test-WindowsBuild.ps1') @PSBoundParameters
