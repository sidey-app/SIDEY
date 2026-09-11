#requires -Version 5.1

[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$PublishDirectory)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$windowsScriptsDirectory = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$publishDirectoryPath = (Resolve-Path -LiteralPath $PublishDirectory).Path
$fixtureDirectory = Join-Path ([IO.Path]::GetTempPath()) "SIDEY-Publish-Guard-$([guid]::NewGuid().ToString('N'))"
$fixtureRuntimeDirectory = Join-Path $fixtureDirectory 'Runtime'
[IO.Directory]::CreateDirectory($fixtureRuntimeDirectory) | Out-Null
try {
    foreach ($name in @('SIDEY.Host.runtimeconfig.json', 'SIDEY.Host.deps.json')) {
        Copy-Item -LiteralPath (Join-Path $publishDirectoryPath "Runtime/$name") -Destination $fixtureRuntimeDirectory
    }
    foreach ($name in @('Microsoft.WindowsAppRuntime.Bootstrap.dll', 'Microsoft.WindowsAppRuntime.Bootstrap.Net.dll', 'Microsoft.WinUI.dll')) {
        [IO.File]::WriteAllText((Join-Path $fixtureRuntimeDirectory $name), 'managed projection/bootstrap fixture')
    }
    foreach ($name in @('coreclr.dll', 'System.Private.CoreLib.dll', 'Microsoft.UI.Xaml.dll',
        'DirectML.dll', 'WindowsAppRuntimeInstall.exe', 'runtime.msix')) {
        $probeFilePath = Join-Path $fixtureRuntimeDirectory $name
        [IO.File]::WriteAllText($probeFilePath, 'forbidden payload')
        $rejected = $false
        try { & (Join-Path $windowsScriptsDirectory 'Test-FrameworkDependentPublish.ps1') -PublishDirectory $fixtureDirectory }
        catch { $rejected = $_.Exception.Message -like 'Shared runtime payload found:*' }
        Remove-Item -LiteralPath $probeFilePath -Force
        if (-not $rejected) { throw "Publish validation did not reject $name" }
        Write-Host "Rejected=$name"
    }
    [IO.Directory]::CreateDirectory((Join-Path $fixtureRuntimeDirectory 'Assets')) | Out-Null
    $rejected = $false
    try { & (Join-Path $windowsScriptsDirectory 'Test-FrameworkDependentPublish.ps1') -PublishDirectory $fixtureDirectory }
    catch { $rejected = $_.Exception.Message -like 'Duplicate Runtime/Assets*' }
    if (-not $rejected) { throw 'Publish validation did not reject duplicate Assets.' }
    Write-Host 'Rejected=Runtime/Assets'
}
finally {
    $fixtureDirectoryPath = [IO.Path]::GetFullPath($fixtureDirectory)
    if ([IO.Directory]::GetParent($fixtureDirectoryPath).FullName -ne
        [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -or
        [IO.Path]::GetFileName($fixtureDirectoryPath) -notlike 'SIDEY-Publish-Guard-*') {
        throw 'Unsafe publish test cleanup path.'
    }
    Remove-Item -LiteralPath $fixtureDirectoryPath -Recurse -Force
}
Write-Host 'PublishGuardTests=true; RejectedPayloads=7'
