#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Version
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Sidey.PowerShell.psm1') -Force
$repositoryRootPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$releaseManifestPath = Join-Path $repositoryRootPath 'release/windows.json'
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = [string](Get-Content -LiteralPath $releaseManifestPath -Raw -Encoding UTF8 |
        ConvertFrom-Json).version
}
if ($Version -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
    throw "Windows build version must contain three numeric parts: $Version"
}
$solutionPath = Join-Path $repositoryRootPath 'windows/SIDEY.Windows.slnx'
$publishDirectory = Join-Path $repositoryRootPath 'build/windows/publish-smoke'

Push-Location (Join-Path $repositoryRootPath 'windows')
try {
    Invoke-SideyNativeCommand `
        -FilePath 'dotnet' `
        -ArgumentList @('restore', $solutionPath) `
        -Description 'dotnet restore'
    Invoke-SideyNativeCommand `
        -FilePath 'dotnet' `
        -ArgumentList @('build', $solutionPath, '--configuration', 'Release', '--no-restore') `
        -Description 'Windows solution build'
    Invoke-SideyNativeCommand `
        -FilePath 'dotnet' `
        -ArgumentList @(
            'test', $solutionPath,
            '--configuration', 'Release',
            '--no-restore',
            '--no-build'
        ) `
        -Description 'Windows solution tests'
    Invoke-SideyNativeCommand `
        -FilePath 'dotnet' `
        -ArgumentList @(
            'publish',
            (Join-Path $repositoryRootPath 'windows/src/Sidey.App/Sidey.App.csproj'),
            '--configuration', 'Release',
            '--runtime', 'win-x64',
            '--self-contained', 'false',
            '--no-restore',
            '-p:WindowsAppSDKSelfContained=false',
            "-p:Version=$Version",
            "-p:FileVersion=$Version.0",
            "-p:AssemblyVersion=$Version.0",
            '-p:PublishSingleFile=false',
            '--output', $publishDirectory
        ) `
        -Description 'Windows smoke publish'
    & (Join-Path $PSScriptRoot 'tests/Test-PowerShellSupport.ps1')
    & (Join-Path $PSScriptRoot 'tests/Test-RuntimePrerequisites.ps1')
    & (Join-Path $PSScriptRoot 'Test-FrameworkDependentPublish.ps1') `
        -PublishDirectory $publishDirectory
    Invoke-SideyNativeCommand `
        -FilePath 'powershell.exe' `
        -ArgumentList @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $repositoryRootPath 'windows/installer/Sidey.Setup/SetupRuntime.ps1')
        ) `
        -Description 'Runtime prerequisite setup'
    & (Join-Path $PSScriptRoot 'Test-PublishedApplication.ps1') `
        -PublishDirectory $publishDirectory
}
finally {
    Pop-Location
}
