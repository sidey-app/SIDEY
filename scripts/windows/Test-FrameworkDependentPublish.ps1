#requires -Version 5.1

[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$PublishDirectory)

& (Join-Path $PSScriptRoot 'tests/Test-FrameworkDependentPublish.ps1') @PSBoundParameters
