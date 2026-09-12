#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repositoryRootPath = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$installerSourceDirectory = Join-Path $repositoryRootPath 'windows/installer/Sidey.Setup'
$prerequisiteConfiguration = Get-Content -LiteralPath (Join-Path $installerSourceDirectory 'prerequisites.json') -Raw | ConvertFrom-Json
. (Join-Path $installerSourceDirectory 'Prerequisites.ps1')
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
Assert-True (Test-SideyVisualCppVersion 'v14.50.35719.0' '14.50.35719.0') 'Accept the required Visual C++ v14 runtime.'
foreach ($version in @('', '14.44.35211.0', '13.50.35719.0', '15.0.0.0')) {
    Assert-True (-not (Test-SideyVisualCppVersion $version '14.50.35719.0')) 'Reject missing, old, or incompatible Visual C++ runtimes.'
}
$runtimePackages = @($prerequisiteConfiguration.windowsAppRuntime.packages | ForEach-Object {
    [pscustomobject]@{ PackageFamilyName = $_.family; Version = $_.minimumVersion; Architecture = 'X64'; Status = 'Ok' }
})
Assert-True (Test-SideyRuntimePackages $runtimePackages $prerequisiteConfiguration.windowsAppRuntime.packages) 'All required packages should qualify.'
for ($index = 0; $index -lt $runtimePackages.Count; $index++) {
    $incompletePackages = @($runtimePackages | Where-Object { $_ -ne $runtimePackages[$index] })
    Assert-True (-not (Test-SideyRuntimePackages $incompletePackages $prerequisiteConfiguration.windowsAppRuntime.packages)) 'Partial runtime must not qualify.'
}
foreach ($propertyMutation in @(@('Architecture', 'X86'), @('Version', '1.0.0.0'), @('Status', 'Modified'), @('PackageFamilyName', 'Fake_8wekyb3d8bbwe'))) {
    $originalValue = $runtimePackages[0].($propertyMutation[0])
    $runtimePackages[0].($propertyMutation[0]) = $propertyMutation[1]
    Assert-True (-not (Test-SideyRuntimePackages $runtimePackages $prerequisiteConfiguration.windowsAppRuntime.packages)) 'Wrong architecture/version/status/publisher must fail.'
    $runtimePackages[0].($propertyMutation[0]) = $originalValue
}
foreach ($url in @('http://download.microsoft.com/runtime.exe', 'https://download.microsoft.com.evil.example/runtime.exe',
    'https://example.com/runtime.exe', 'https://aka.ms:444/runtime.exe', 'https://user@aka.ms/runtime.exe')) {
    Assert-Throws { Assert-SideyMicrosoftUri $url } 'Reject untrusted download/redirect.'
}
Assert-SideyMicrosoftUri $prerequisiteConfiguration.dotnet.url
Assert-SideyMicrosoftUri $prerequisiteConfiguration.windowsAppRuntime.url
Assert-SideyMicrosoftUri $prerequisiteConfiguration.visualCpp.url
Assert-True (Test-SideyMicrosoftSignerSubject 'CN=.NET, O=Microsoft Corporation, L=Redmond, S=Washington, C=US') 'Accept the current .NET product signer.'
Assert-True (Test-SideyMicrosoftSignerSubject 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US') 'Accept a Microsoft corporate signer.'
foreach ($subject in @('', 'CN=Microsoft Corporation', 'CN=.NET, O=Not Microsoft Corporation, C=US',
    'CN=.NET, O=Microsoft Corporation Fake, C=US')) {
    Assert-True (-not (Test-SideyMicrosoftSignerSubject $subject)) 'Reject a missing or non-Microsoft publisher organization.'
}

$errorMappings = @(
    @('0x80073CF0', 'PACKAGE_CORRUPTED'), @('0x80073CF3', 'DEPENDENCY_CONFLICT'),
    @('0x80073CF4', 'DISK_FULL'), @('0x80073CF5', 'DOWNLOAD_FAILED'),
    @('0x80073CF6', 'PACKAGE_REGISTRATION_FAILED'), @('0x80073CF9', 'UNKNOWN_ERROR'),
    @('0x80073CFB', 'ALREADY_INSTALLED'), @('0x80073CFD', 'DEPENDENCY_MISSING'),
    @('0x80073CFE', 'PACKAGE_REPOSITORY_CORRUPTED'), @('0x80073CFF', 'BLOCKED_BY_POLICY'),
    @('0x80073D01', 'BLOCKED_BY_POLICY'), @('0x80073D02', 'APP_IN_USE'),
    @('0x80073D06', 'ALREADY_INSTALLED'), @('0x80073D10', 'INCOMPATIBLE_SYSTEM'),
    @('0x80073D28', 'PERMISSION_DENIED'), @('0x80080203', 'PACKAGE_CORRUPTED'),
    @('0x80080206', 'PACKAGE_CORRUPTED'), @('0x80080207', 'PACKAGE_CORRUPTED'),
    @('0x800B0100', 'SIGNATURE_ERROR'), @('0x800B0109', 'SIGNATURE_ERROR'),
    @('0x80070005', 'PERMISSION_DENIED'), @('0x80070070', 'DISK_FULL'),
    @('12002', 'NETWORK_ERROR'), @('12007', 'NETWORK_ERROR'), @('12029', 'NETWORK_ERROR'),
    @('12030', 'NETWORK_ERROR'), @('12031', 'NETWORK_ERROR'), @('12163', 'NETWORK_ERROR'),
    @('1602', 'USER_CANCELLED'), @('1603', 'UNKNOWN_ERROR'),
    @('1618', 'ANOTHER_INSTALLATION_RUNNING'), @('1619', 'PACKAGE_CORRUPTED'),
    @('1620', 'PACKAGE_CORRUPTED'), @('1625', 'BLOCKED_BY_POLICY'),
    @('1633', 'INCOMPATIBLE_SYSTEM'), @('1638', 'ALREADY_INSTALLED')
)
foreach ($mapping in $errorMappings) {
    $result = Resolve-SideyInstallerError $mapping[0] 'TEST' 'INSTALL'
    Assert-True ($result.Status -eq 'FAILED' -and $result.Category -eq $mapping[1]) `
        "Normalize $($mapping[0]) as $($mapping[1])."
}
Assert-True ((Resolve-SideyInstallerError -2147009281 'APPX' 'INSTALL').NativeCode -eq '0x80073CFF') `
    'Preserve a signed HRESULT as canonical hexadecimal.'
Assert-True ((Resolve-SideyInstallerError 0 'MSI' 'INSTALL').Status -eq 'SUCCESS') 'MSI 0 is success.'
foreach ($code in @(1641, 3010)) {
    $result = Resolve-SideyInstallerError $code 'MSI' 'INSTALL'
    Assert-True ($result.Status -eq 'SUCCESS_REBOOT_REQUIRED' -and $result.Category -eq 'REBOOT_REQUIRED') `
        "MSI $code is successful and requires a reboot."
}
$unknown = Resolve-SideyInstallerError '0x8ABCDEF0' 'TEST' 'INSTALL'
Assert-True ($unknown.Status -eq 'FAILED' -and $unknown.Category -eq 'UNKNOWN_ERROR' -and
    $unknown.NativeCode -eq '0x8ABCDEF0') 'Unknown errors retain their native code and use the fallback category.'
Assert-True ((Get-SideyDownloadCategoryHint ([Net.WebException]::new('timeout', [Net.WebExceptionStatus]::Timeout))) `
    -eq 'NETWORK_ERROR') 'Classify managed connection failures as network errors.'
Assert-True ((Get-SideyDownloadCategoryHint ([Exception]::new('HTTP failure'))) -eq 'DOWNLOAD_FAILED') `
    'Keep non-connection download failures distinct from network errors.'

# Exercise the real orchestration with only OS/network boundaries replaced.
# No Microsoft installs, app termination, or real SIDEY data mutations in tests.
foreach ($scenario in @('present', 'missing', 'download-failure', 'signature-failure', 'install-failure',
    'cancel', 'restart', 'restart-initiated', 'postcheck-failure', 'winapp-failure', 'check-only', 'provision-failure')) {
    & {
        . (Join-Path $installerSourceDirectory 'Prerequisites.ps1')
        $script:events = [Collections.Generic.List[string]]::new()
        $script:visualCppReady = $scenario -in @('present', 'winapp-failure')
        $script:netReady = $scenario -in @('present', 'winapp-failure')
        $script:appReady = $scenario -eq 'present'
        function Test-SideyVisualCpp { param($Requirement) return $script:visualCppReady }
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
                if ($Path.EndsWith('vc_redist.x64.exe')) { $script:visualCppReady = $true }
                elseif ($Path.EndsWith('dotnet-runtime-x64.exe')) { $script:netReady = $true }
                else { $script:appReady = $true }
            }
            return 0
        }
        function Enable-SideyRuntimeForAllUsers {
            param($Requirement)
            $script:events.Add('provision')
            if ($scenario -eq 'provision-failure') { throw 'Provisioning denied' }
        }
        $operation = { Install-SideyPrerequisites $prerequisiteConfiguration $testDownloadDirectory -CheckOnly:($scenario -eq 'check-only') -ProvisionAllUsers }
        if ($scenario -in @('present', 'missing')) {
            Assert-True ((& $operation) -eq 0) "$scenario must succeed."
            $expected = if ($scenario -eq 'present') { 'provision' } else { 'download,signature,install,download,signature,install,download,signature,install,provision' }
            Assert-True (($script:events -join ',') -ceq $expected) 'Verify signatures before executing; skip installed runtimes.'
        }
        elseif ($scenario -in @('restart', 'restart-initiated')) {
            $expectedCode = if ($scenario -eq 'restart-initiated') { 1641 } else { 3010 }
            Assert-True ((& $operation) -eq $expectedCode) 'Preserve the native reboot-success code and stop before the next prerequisite.'
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
    $resultPath = Join-Path $testRoot 'InstallerResult.ini'
    $logPath = Join-Path $testRoot 'SIDEY-Setup.log'
    $result = New-SideyInstallerResult -2147009281 'APPX' 'INSTALL' '' 'Windows App Runtime x64' `
        'windowsappruntimeinstall-x64.exe --quiet' '-2147009281' 'policy failure' '1.2.1'
    Write-SideyInstallerResult $result $resultPath $logPath
    $resultText = Get-Content -LiteralPath $resultPath -Raw -Encoding Unicode
    $logText = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8
    Assert-True ($resultText -match 'category=BLOCKED_BY_POLICY' -and $resultText -match 'nativeCode=0x80073CFF') `
        'Write normalized UI handoff data without losing the HRESULT.'
    foreach ($field in @('timestamp=', 'stage=INSTALL', 'source=APPX', 'nativeCode=0x80073CFF',
        'category=BLOCKED_BY_POLICY', 'target=Windows App Runtime x64', 'exitCode=-2147009281',
        'windowsVersion=', 'installerVersion=1.2.1')) {
        Assert-True ($logText.Contains($field)) "Installer log must contain $field."
    }

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
