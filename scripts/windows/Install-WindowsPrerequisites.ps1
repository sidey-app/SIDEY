#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [switch]$ProvisionAllUsers
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repositoryRootPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$probeRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'SIDEY prerequisite setup ' + [Guid]::NewGuid().ToString('N'))
$helperPath = Join-Path $probeRoot 'Sidey.PrerequisiteInstaller.exe'
$resultPath = Join-Path $probeRoot 'result.ini'
$logPath = Join-Path $probeRoot 'setup.log'
$configPath = Join-Path $repositoryRootPath 'windows/installer/Sidey.Setup/prerequisites.json'

[IO.Directory]::CreateDirectory($probeRoot) | Out-Null
& (Join-Path $PSScriptRoot 'New-SideyHelperExecutable.ps1') `
    -SourcePath (Join-Path $repositoryRootPath 'windows/installer/Sidey.Setup/PrerequisiteInstaller.cs') `
    -OutputPath $helperPath `
    -Version $Version -FileVersion "$Version.0" `
    -Title 'SIDEY Prerequisite Installer' `
    -Description 'SIDEY prerequisite detection and installation helper' `
    -IconPath (Join-Path $repositoryRootPath 'windows/src/Sidey.App/Assets/Icons/SideyAppIcon.ico')

$helperArguments = @(
    '--config', $configPath,
    '--download-directory', $probeRoot,
    '--result-path', $resultPath,
    '--log-path', $logPath,
    '--installer-version', $Version
)
if ($ProvisionAllUsers) {
    $helperArguments = @('--provision-all-users') + $helperArguments
}

function ConvertTo-SideyWindowsArgument([string]$Value) {
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    # Start-Process accepts one native command-line string on Windows. Quote
    # embedded quotes and trailing backslashes using CommandLineToArgvW rules.
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

$helperArgumentLine = ($helperArguments | ForEach-Object {
    ConvertTo-SideyWindowsArgument $_
}) -join ' '
$process = Start-Process -FilePath $helperPath -ArgumentList $helperArgumentLine `
    -WindowStyle Hidden -Wait -PassThru
try {
    $exitCode = $process.ExitCode
}
finally {
    $process.Dispose()
}
if ($exitCode -ne 0) {
    $result = if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
        Get-Content -LiteralPath $resultPath -Raw -Encoding Unicode
    }
    else {
        'No installer result was written.'
    }
    throw "Runtime prerequisite setup failed with exit code $exitCode.`n$result`nLog: $logPath"
}

Write-Host "Runtime prerequisites are ready. Log=$logPath"
