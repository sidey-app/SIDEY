#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDirectory,

    [int]$TimeoutSeconds = 30
)

& (Join-Path $PSScriptRoot 'tests/Test-PublishedApplication.ps1') @PSBoundParameters
