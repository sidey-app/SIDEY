#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$HelperPath,
    [string]$Version = '1.3.1',
    [string]$FileVersion = '1.3.1.0'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../Sidey.PowerShell.psm1') -Force

$shell = (Get-Command powershell.exe -ErrorAction Stop).Source
Invoke-SideyNativeCommand `
    -FilePath $shell `
    -ArgumentList @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'exit 0') `
    -Description 'Successful native command test'

$failure = $null
try {
    Invoke-SideyNativeCommand `
        -FilePath $shell `
        -ArgumentList @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'exit 23') `
        -Description 'Expected native command test failure'
}
catch {
    $failure = $_
}

if ($null -eq $failure) {
    throw 'Invoke-SideyNativeCommand accepted a non-zero exit code.'
}
if ($failure.Exception.Message -cne 'Expected native command test failure failed with exit code 23.') {
    throw "Unexpected native command failure message: $($failure.Exception.Message)"
}

$repositoryRootPath = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'SIDEY PowerShell process tests ' + [Guid]::NewGuid().ToString('N'))
$resultPath = Join-Path $testRoot 'process result with spaces.ini'
$logPath = Join-Path $testRoot 'process log with spaces.log'
try {
    [IO.Directory]::CreateDirectory($testRoot) | Out-Null
    if ([string]::IsNullOrWhiteSpace($HelperPath)) {
        $HelperPath = Join-Path $testRoot 'Sidey.PrerequisiteInstaller.exe'
        & (Join-Path $repositoryRootPath 'scripts/windows/New-SideyHelperExecutable.ps1') `
            -SourcePath (Join-Path $repositoryRootPath 'windows/installer/Sidey.Setup/PrerequisiteInstaller.cs') `
            -OutputPath $HelperPath `
            -Version $Version -FileVersion $FileVersion `
            -Title 'SIDEY Prerequisite Installer' `
            -Description 'SIDEY prerequisite installer process probe' `
            -IconPath (Join-Path $repositoryRootPath 'windows/src/Sidey.App/Assets/Icons/SideyAppIcon.ico')
    }
    $HelperPath = (Resolve-Path -LiteralPath $HelperPath).Path
    $commandDescription = 'quote"inside C:\trailing\'
    $exitCode = Invoke-SideyWindowsProcess `
        -FilePath $HelperPath `
        -ArgumentList @(
            '--normalize-error', '--native-code', '0', '--source', 'TEST', '--stage', 'CHECK',
            '--target', 'target with spaces', '--command-description', $commandDescription,
            '--result-path', $resultPath, '--log-path', $logPath,
            '--installer-version', $Version)
    if ($exitCode -ne 0) {
        throw "WinExe process success code was not preserved: $exitCode"
    }
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw 'WinExe process invocation returned before the completion marker was written.'
    }
    $result = [IO.File]::ReadAllText($resultPath, [Text.Encoding]::Unicode)
    if (-not $result.Contains("target=target with spaces") -or
        -not $result.Contains("command=$commandDescription")) {
        throw 'WinExe process arguments did not round-trip through the Windows command line.'
    }
    $exitCode = Invoke-SideyWindowsProcess `
        -FilePath $HelperPath `
        -ArgumentList @('--sidey-invalid-verification-argument')
    if ($exitCode -ne 64) {
        throw "WinExe process failure code was not preserved: $exitCode"
    }
    $exitCode = Invoke-SideyWindowsProcess -FilePath $HelperPath
    if ($exitCode -ne 64) {
        throw "WinExe process with no arguments returned an unexpected code: $exitCode"
    }
}
finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ([IO.Directory]::GetParent($resolvedTestRoot).FullName -cne $expectedParent -or
        [IO.Path]::GetFileName($resolvedTestRoot) -notlike 'SIDEY PowerShell process tests *') {
        throw 'Unsafe PowerShell process test cleanup path.'
    }
    if (Test-Path -LiteralPath $resolvedTestRoot) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}

Write-Host 'PowerShell native command helper tests passed.'
