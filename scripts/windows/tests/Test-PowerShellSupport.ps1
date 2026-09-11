#requires -Version 5.1

[CmdletBinding()]
param()

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

Write-Host 'PowerShell native command helper tests passed.'
