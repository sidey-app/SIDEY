$ErrorActionPreference = 'Stop'
$setupRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../windows/installer/Sidey.Setup'))
$configuration = Get-Content -LiteralPath (Join-Path $setupRoot 'prerequisites.json') -Raw | ConvertFrom-Json
. (Join-Path $setupRoot 'Prerequisites.ps1')
$script:assertions = 0
$testDownloadDirectory = Join-Path ([IO.Path]::GetTempPath()) "SIDEY-Mock-Downloads-$([guid]::NewGuid().ToString('N'))"
function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:assertions++
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert-True $failed $Message
}

Assert-True (Test-SideyDotNetVersion @('8.0.30', '10.0.11') '10.0.0') 'Accept .NET 10 servicing updates.'
foreach ($versions in @(@('8.0.30'), @('11.0.0'), @('10.0.0-preview.1'), @('10.1.0'), @())) {
    Assert-True (-not (Test-SideyDotNetVersion $versions '10.0.0')) 'Reject incompatible .NET runtimes.'
}
$packages = @($configuration.windowsAppRuntime.packages | ForEach-Object {
    [pscustomobject]@{ PackageFamilyName = $_.family; Version = $_.minimumVersion; Architecture = 'X64'; Status = 'Ok' }
})
Assert-True (Test-SideyRuntimePackages $packages $configuration.windowsAppRuntime.packages) 'All required packages should qualify.'
for ($index = 0; $index -lt $packages.Count; $index++) {
    $withoutOne = @($packages | Where-Object { $_ -ne $packages[$index] })
    Assert-True (-not (Test-SideyRuntimePackages $withoutOne $configuration.windowsAppRuntime.packages)) 'Partial runtime must not qualify.'
}
foreach ($change in @(@('Architecture', 'X86'), @('Version', '1.0.0.0'), @('Status', 'Modified'), @('PackageFamilyName', 'Fake_8wekyb3d8bbwe'))) {
    $original = $packages[0].($change[0])
    $packages[0].($change[0]) = $change[1]
    Assert-True (-not (Test-SideyRuntimePackages $packages $configuration.windowsAppRuntime.packages)) 'Wrong architecture/version/status/publisher must fail.'
    $packages[0].($change[0]) = $original
}
foreach ($url in @('http://download.microsoft.com/runtime.exe', 'https://download.microsoft.com.evil.example/runtime.exe',
    'https://example.com/runtime.exe', 'https://aka.ms:444/runtime.exe', 'https://user@aka.ms/runtime.exe')) {
    Assert-Throws { Assert-SideyMicrosoftUri $url } 'Reject untrusted download/redirect.'
}
Assert-SideyMicrosoftUri $configuration.dotnet.url
Assert-SideyMicrosoftUri $configuration.windowsAppRuntime.url

# Exercise the real orchestration with only OS/network boundaries replaced.
# No Microsoft installs, app termination, or real SIDEY data mutations in tests.
foreach ($scenario in @('present', 'missing', 'download-failure', 'signature-failure', 'install-failure',
    'cancel', 'restart', 'restart-initiated', 'postcheck-failure', 'winapp-failure', 'check-only', 'provision-failure')) {
    & {
        . (Join-Path $setupRoot 'Prerequisites.ps1')
        $script:events = [Collections.Generic.List[string]]::new()
        $script:netReady = $scenario -in @('present', 'winapp-failure')
        $script:appReady = $scenario -eq 'present'
        function Test-SideyDotNet { param($Requirement) return $script:netReady }
        function Test-SideyWindowsAppRuntime { param($Requirement) return $script:appReady }
        function Save-SideyMicrosoftInstaller {
            param($Uri, $Destination)
            $script:events.Add('download')
            if ($scenario -eq 'download-failure') { throw 'Offline' }
        }
        function Assert-SideyMicrosoftSignature {
            param($Path)
            $script:events.Add('signature')
            if ($scenario -eq 'signature-failure') { throw 'Untrusted signature' }
        }
        function Invoke-SideyRuntimeInstaller {
            param($Path, $Arguments)
            $script:events.Add('install')
            if ($scenario -eq 'restart') { return 3010 }
            if ($scenario -eq 'restart-initiated') { return 1641 }
            if ($scenario -eq 'cancel') { return 1602 }
            if ($scenario -in @('install-failure', 'winapp-failure')) { return 1603 }
            if ($scenario -ne 'postcheck-failure') {
                if ($Path.EndsWith('dotnet-runtime-x64.exe')) { $script:netReady = $true }
                else { $script:appReady = $true }
            }
            return 0
        }
        function Enable-SideyRuntimeForAllUsers {
            param($Requirement)
            $script:events.Add('provision')
            if ($scenario -eq 'provision-failure') { throw 'Provisioning denied' }
        }
        $operation = { Install-SideyPrerequisites $configuration $testDownloadDirectory -CheckOnly:($scenario -eq 'check-only') -ProvisionAllUsers }
        if ($scenario -in @('present', 'missing')) {
            Assert-True ((& $operation) -eq 0) "$scenario must succeed."
            $expected = if ($scenario -eq 'present') { 'provision' } else { 'download,signature,install,download,signature,install,provision' }
            Assert-True (($script:events -join ',') -ceq $expected) 'Verify signatures before executing; skip installed runtimes.'
        }
        elseif ($scenario -in @('restart', 'restart-initiated')) {
            Assert-True ((& $operation) -eq 3010) 'Return restart without proceeding to the next prerequisite.'
            Assert-True ($script:events.Count -eq 3) 'Stop after reboot result.'
        }
        else { Assert-Throws $operation "$scenario must block app replacement." }
        if ($scenario -in @('download-failure', 'signature-failure', 'check-only')) {
            Assert-True (-not $script:events.Contains('install')) 'Never execute an unverified download.'
        }
    }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) "SIDEY-Prerequisite-Tests-$([guid]::NewGuid().ToString('N'))"
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
try {
    $installRoot = Join-Path $testRoot 'Install'
    $runtimeRoot = Join-Path $installRoot 'Runtime'
    [IO.Directory]::CreateDirectory((Join-Path $runtimeRoot 'en-US')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $runtimeRoot 'coreclr.dll'), 'old runtime')
    Assert-Throws { Assert-SideyMicrosoftSignature (Join-Path $runtimeRoot 'coreclr.dll') } 'Reject unsigned installer bytes.'
    [IO.File]::WriteAllText((Join-Path $runtimeRoot 'Microsoft.UI.Xaml.dll'), 'old WinUI')
    [IO.File]::WriteAllText((Join-Path $runtimeRoot 'en-US/resources.pri'), 'old resources')
    [IO.File]::WriteAllText((Join-Path $installRoot 'SIDEY.exe'), 'launcher')
    $sharedRoot = Join-Path $testRoot 'SharedRuntime'
    [IO.Directory]::CreateDirectory($sharedRoot) | Out-Null
    [IO.File]::WriteAllText((Join-Path $sharedRoot 'coreclr.dll'), 'shared runtime')
    Remove-SideyPrivateRuntime $installRoot
    Assert-True (-not (Test-Path -LiteralPath $runtimeRoot)) 'Remove all legacy private runtime files.'
    Assert-True (Test-Path -LiteralPath (Join-Path $installRoot 'SIDEY.exe')) 'Preserve files outside private Runtime.'
    Assert-True (Test-Path -LiteralPath (Join-Path $sharedRoot 'coreclr.dll')) 'Preserve shared runtimes.'
    Remove-SideyPrivateRuntime $installRoot
    New-Item -ItemType Junction -Path $runtimeRoot -Target $sharedRoot | Out-Null
    try {
        Assert-Throws { Remove-SideyPrivateRuntime $installRoot } 'Reject a Runtime junction.'
        Assert-True (Test-Path -LiteralPath (Join-Path $sharedRoot 'coreclr.dll')) 'Never follow a junction into shared runtimes.'
    }
    finally { [IO.Directory]::Delete($runtimeRoot) }
    Assert-Throws { Remove-SideyPrivateRuntime ([IO.Path]::GetPathRoot($testRoot)) } 'Reject drive root.'
}
finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ([IO.Directory]::GetParent($resolvedTestRoot).FullName -ne $expectedParent -or
        [IO.Path]::GetFileName($resolvedTestRoot) -notlike 'SIDEY-Prerequisite-Tests-*') {
        throw 'Unsafe test cleanup path.'
    }
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}
Write-Host "PrerequisiteTests=true; Assertions=$script:assertions"
