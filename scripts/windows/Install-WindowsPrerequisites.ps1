#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Sidey.PowerShell.psm1') -Force
$repositoryRootPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$probeRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'SIDEY prerequisite setup ' + [Guid]::NewGuid().ToString('N'))
$helperPath = Join-Path $probeRoot 'Sidey.PrerequisiteInstaller.exe'
$desktopUserRunnerPath = Join-Path $probeRoot 'Sidey.SetupSupport.exe'
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
& (Join-Path $PSScriptRoot 'New-SideyHelperExecutable.ps1') `
    -SourcePath (Join-Path $repositoryRootPath 'windows/src/Sidey.Uninstaller/Program.cs') `
    -OutputPath $desktopUserRunnerPath `
    -Version $Version -FileVersion "$Version.0" `
    -Title 'SIDEY Setup Support' `
    -Description 'SIDEY desktop-user process runner' `
    -IconPath (Join-Path $repositoryRootPath 'windows/src/Sidey.App/Assets/Icons/SideyAppIcon.ico')

$helperArguments = @(
    '--desktop-user-runner', $desktopUserRunnerPath,
    '--config', $configPath,
    '--download-directory', $probeRoot,
    '--result-path', $resultPath,
    '--log-path', $logPath,
    '--installer-version', $Version
)
$exitCode = Invoke-SideyWindowsProcess -FilePath $helperPath -ArgumentList $helperArguments
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
