[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$PublishDir)
$ErrorActionPreference = 'Stop'
$publishRoot = (Resolve-Path -LiteralPath $PublishDir).Path
$fixture = Join-Path ([IO.Path]::GetTempPath()) "SIDEY-Publish-Guard-$([guid]::NewGuid().ToString('N'))"
$fixtureRuntime = Join-Path $fixture 'Runtime'
[IO.Directory]::CreateDirectory($fixtureRuntime) | Out-Null
try {
    foreach ($name in @('SIDEY.Host.runtimeconfig.json', 'SIDEY.Host.deps.json')) {
        Copy-Item -LiteralPath (Join-Path $publishRoot "Runtime/$name") -Destination $fixtureRuntime
    }
    foreach ($name in @('Microsoft.WindowsAppRuntime.Bootstrap.dll', 'Microsoft.WindowsAppRuntime.Bootstrap.Net.dll', 'Microsoft.WinUI.dll')) {
        [IO.File]::WriteAllText((Join-Path $fixtureRuntime $name), 'managed projection/bootstrap fixture')
    }
    foreach ($name in @('coreclr.dll', 'System.Private.CoreLib.dll', 'Microsoft.UI.Xaml.dll',
        'DirectML.dll', 'WindowsAppRuntimeInstall.exe', 'runtime.msix')) {
        $probe = Join-Path $fixtureRuntime $name
        [IO.File]::WriteAllText($probe, 'forbidden payload')
        $rejected = $false
        try { & (Join-Path $PSScriptRoot 'verify-framework-publish.ps1') -PublishDir $fixture }
        catch { $rejected = $_.Exception.Message -like 'Shared runtime payload found:*' }
        Remove-Item -LiteralPath $probe -Force
        if (-not $rejected) { throw "Publish validation did not reject $name" }
        Write-Host "Rejected=$name"
    }
    [IO.Directory]::CreateDirectory((Join-Path $fixtureRuntime 'Assets')) | Out-Null
    $rejected = $false
    try { & (Join-Path $PSScriptRoot 'verify-framework-publish.ps1') -PublishDir $fixture }
    catch { $rejected = $_.Exception.Message -like 'Duplicate Runtime/Assets*' }
    if (-not $rejected) { throw 'Publish validation did not reject duplicate Assets.' }
    Write-Host 'Rejected=Runtime/Assets'
}
finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    if ([IO.Directory]::GetParent($resolvedFixture).FullName -ne
        [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -or
        [IO.Path]::GetFileName($resolvedFixture) -notlike 'SIDEY-Publish-Guard-*') {
        throw 'Unsafe publish test cleanup path.'
    }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
Write-Host 'PublishGuardTests=true; RejectedPayloads=7'
