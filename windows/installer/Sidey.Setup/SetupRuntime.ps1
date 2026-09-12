[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$ProvisionAllUsers,
    [string]$InstallDirectory,
    [string]$ResultPath,
    [string]$LogPath,
    [string]$InstallerVersion = 'unknown',
    [string]$NativeCode,
    [string]$Source = 'UNKNOWN',
    [string]$Stage = 'INSTALL',
    [string]$CategoryHint,
    [string]$Target,
    [string]$CommandDescription,
    [string]$ExitCode,
    [string]$Message
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    if (-not [Environment]::Is64BitProcess) { throw '64-bit Windows PowerShell is required.' }
    . (Join-Path $PSScriptRoot 'InstallerErrors.ps1')
    if (-not [string]::IsNullOrWhiteSpace($NativeCode)) {
        $result = New-SideyInstallerResult $NativeCode $Source $Stage $CategoryHint $Target `
            $CommandDescription $ExitCode $Message $InstallerVersion
        Write-SideyInstallerResult $result $ResultPath $LogPath
        exit 0
    }
    . (Join-Path $PSScriptRoot 'Prerequisites.ps1')
    if ($InstallDirectory) {
        Remove-SideyPrivateRuntime $InstallDirectory
        $result = New-SideyInstallerResult 0 'FILESYSTEM' 'CLEANUP' '' 'SIDEY private Runtime' `
            'Remove-SideyPrivateRuntime' 0 '' $InstallerVersion
        Write-SideyInstallerResult $result $ResultPath $LogPath
        exit 0
    }
    $configuration = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'prerequisites.json') -Raw | ConvertFrom-Json
    $code = Install-SideyPrerequisites $configuration $PSScriptRoot -CheckOnly:$CheckOnly -ProvisionAllUsers:$ProvisionAllUsers
    $result = New-SideyInstallerResult $code 'PREREQUISITE' 'INSTALL' '' 'SIDEY required runtimes' `
        'Install-SideyPrerequisites' $code '' $InstallerVersion
    Write-SideyInstallerResult $result $ResultPath $LogPath
    exit $code
}
catch {
    if ($null -eq (Get-Command ConvertTo-SideyInstallerFailureResult -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'InstallerErrors.ps1')
    }
    $result = ConvertTo-SideyInstallerFailureResult $_.Exception $InstallerVersion
    Write-SideyInstallerResult $result $ResultPath $LogPath
    Write-Host "Installer error: $($result.Category) ($($result.NativeCode))"
    exit 1
}
