[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$ProvisionAllUsers,
    [string]$InstallDirectory
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    if (-not [Environment]::Is64BitProcess) { throw '64-bit Windows PowerShell is required.' }
    . (Join-Path $PSScriptRoot 'Prerequisites.ps1')
    if ($InstallDirectory) {
        Remove-SideyPrivateRuntime $InstallDirectory
        exit 0
    }
    $configuration = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'prerequisites.json') -Raw | ConvertFrom-Json
    $code = Install-SideyPrerequisites $configuration $PSScriptRoot -CheckOnly:$CheckOnly -ProvisionAllUsers:$ProvisionAllUsers
    exit $code
}
catch {
    Write-Host $_.Exception.Message
    exit 1
}
