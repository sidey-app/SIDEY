#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$HelperPath,
    [string]$Version = '1.3.1',
    [string]$FileVersion = '1.3.1.0'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$source = Join-Path $root 'windows/installer/Sidey.Setup/PrerequisiteInstaller.cs'
$configuration = Join-Path $root 'windows/installer/Sidey.Setup/prerequisites.json'
$script:assertions = 0
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('SIDEY prerequisite helper tests ' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:assertions++
}

function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert-True $failed $Message
}

function Invoke-Static([Type]$Type, [string]$Name, [object[]]$Arguments) {
    $flags = [Reflection.BindingFlags]::Static -bor [Reflection.BindingFlags]::NonPublic
    $method = @($Type.GetMethods($flags) | Where-Object {
        $_.Name -ceq $Name -and $_.GetParameters().Count -eq $Arguments.Count
    })
    if ($method.Count -ne 1) { throw "Unable to resolve $($Type.FullName).$Name." }
    $invokeArguments = [object[]]::new($Arguments.Count)
    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        $argument = $Arguments[$index]
        $targetType = $method[0].GetParameters()[$index].ParameterType
        if ($targetType -eq [Collections.Generic.IEnumerable[string]]) {
            $invokeArguments.SetValue([string[]]@($argument), $index)
        } elseif ($targetType -eq [string]) {
            $invokeArguments.SetValue([string]$argument, $index)
        } elseif ($argument -is [Management.Automation.PSObject]) {
            $invokeArguments.SetValue($argument.BaseObject, $index)
        } else {
            $invokeArguments.SetValue($argument, $index)
        }
    }
    return $method[0].Invoke($null, $invokeArguments)
}

function Get-Field($Value, [string]$Name) {
    $flags = [Reflection.BindingFlags]::Instance -bor [Reflection.BindingFlags]::NonPublic
    return $Value.GetType().GetField($Name, $flags).GetValue($Value)
}

function Quote-Argument([string]$Value) {
    return '"' + $Value.Replace('\', '\').Replace('"', '\"') + '"'
}

function Start-Helper([string[]]$Arguments, [string]$WorkingDirectory = $testRoot) {
    $argumentLine = ($Arguments | ForEach-Object { Quote-Argument $_ }) -join ' '
    return Start-Process -FilePath $HelperPath -ArgumentList $argumentLine `
        -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -Wait -PassThru
}

function Test-DotNetVersions([string[]]$Candidates, [version]$Minimum) {
    $arguments = [object[]]::new(2)
    $arguments.SetValue($Candidates, 0)
    $arguments.SetValue($Minimum, 1)
    return Invoke-Static $versions 'HasDotNetVersion' $arguments
}

try {
    if ([string]::IsNullOrWhiteSpace($HelperPath)) {
        $HelperPath = Join-Path $testRoot 'Sidey.PrerequisiteInstaller.exe'
        & (Join-Path $root 'scripts/windows/New-SideyHelperExecutable.ps1') `
            -SourcePath $source -OutputPath $HelperPath `
            -Title 'SIDEY Prerequisite Installer' -Description 'SIDEY prerequisite installer' `
            -Version $Version -FileVersion $FileVersion `
            -IconPath (Join-Path $root 'windows/src/Sidey.App/Assets/Icons/SideyAppIcon.ico')
    }
    $HelperPath = (Resolve-Path -LiteralPath $HelperPath).Path
    $assembly = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($HelperPath))
    $versions = $assembly.GetType('Sidey.Setup.Prerequisites.VersionChecks', $true)
    $download = $assembly.GetType('Sidey.Setup.Prerequisites.MicrosoftDownload', $true)
    $signer = $assembly.GetType('Sidey.Setup.Prerequisites.AuthenticodeVerifier', $true)
    $errors = $assembly.GetType('Sidey.Setup.Prerequisites.InstallerErrors', $true)
    $installPolicy = $assembly.GetType('Sidey.Setup.Prerequisites.PrerequisiteInstallPolicy', $true)
    $prerequisiteService = $assembly.GetType('Sidey.Setup.Prerequisites.PrerequisiteService', $true)
    $platform = $assembly.GetType('Sidey.Setup.Prerequisites.PlatformSupport', $true)
    $desktopUser = $assembly.GetType('Sidey.Setup.Prerequisites.DesktopUserIdentity', $true)
    $packageQuery = $assembly.GetType('Sidey.Setup.Prerequisites.WindowsPackageQuery', $true)
    $packageStatus = $assembly.GetType('Sidey.Setup.Prerequisites.WindowsPackageStatus', $true)
    $configType = $assembly.GetType('Sidey.Setup.Prerequisites.PrerequisiteConfiguration', $true)

    $lockedExecutablePath = Join-Path $testRoot 'where.exe'
    Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32/where.exe') `
        -Destination $lockedExecutablePath
    $downloadHandle = [IO.File]::Open(
        $lockedExecutablePath,
        [IO.FileMode]::Open,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::Read)
    $lockedExecutable = $null
    try {
        $lockedExecutable = Invoke-Static $prerequisiteService `
            'TransitionToExecutableReadLock' @($lockedExecutablePath, $downloadHandle)
        $downloadHandle = $null
        Assert-Throws {
            [IO.File]::Open(
                $lockedExecutablePath,
                [IO.FileMode]::Open,
                [IO.FileAccess]::Write,
                [IO.FileShare]::ReadWrite).Dispose()
        } 'Reject writes after transitioning the prerequisite to its executable read lock.'
        Assert-Throws { [IO.File]::Delete($lockedExecutablePath) } `
            'Reject replacement after transitioning the prerequisite to its executable read lock.'
        $lockedProcess = Start-Process -FilePath $lockedExecutablePath `
            -ArgumentList '/?' `
            -WindowStyle Hidden -Wait -PassThru
        Assert-True ($lockedProcess.ExitCode -eq 0) `
            'Allow Windows to execute a verified prerequisite while the anti-replacement handle remains open.'
    }
    finally {
        if ($null -ne $lockedExecutable) { $lockedExecutable.Dispose() }
        if ($null -ne $downloadHandle) { $downloadHandle.Dispose() }
    }

    Assert-True (Test-DotNetVersions -Candidates ([string[]]@('8.0.30', '10.0.11')) -Minimum ([version]'10.0.0')) `
        'Accept .NET 10 servicing updates.'
    foreach ($candidates in @(
        ,([string[]]@('8.0.30')),
        ,([string[]]@('11.0.0')),
        ,([string[]]@('10.0.0-preview.1')),
        ,([string[]]@('10.1.0')),
        ,([string[]]@()))) {
        Assert-True (-not (Test-DotNetVersions -Candidates ([string[]]$candidates) -Minimum ([version]'10.0.0'))) `
            'Reject incompatible .NET runtimes.'
    }
    Assert-True (Invoke-Static $versions 'HasVisualCppVersion' @('v14.50.35719.0', [version]'14.50.35719.0')) `
        'Accept the required Visual C++ runtime.'
    foreach ($candidate in @('', '14.44.35211.0', '13.50.35719.0', '15.0.0.0')) {
        Assert-True (-not (Invoke-Static $versions 'HasVisualCppVersion' @($candidate, [version]'14.50.35719.0'))) `
            'Reject missing, old, or incompatible Visual C++ runtimes.'
    }
    Assert-True (Invoke-Static $platform 'IsSupportedVersion' @([uint32]10, [uint32]17763)) `
        'Accept Windows 10 version 1809 at the exact build boundary.'
    Assert-True (-not (Invoke-Static $platform 'IsSupportedVersion' @([uint32]10, [uint32]17762))) `
        'Reject Windows builds before Windows 10 version 1809.'
    Assert-True (Invoke-Static $platform 'IsSupportedVersion' @([uint32]11, [uint32]1)) `
        'Allow future Windows major versions.'
    Invoke-Static $platform 'AssertSupported' @() | Out-Null
    $script:assertions++
    $actualWindowsVersion = [string](Invoke-Static $platform 'GetActualVersionString' @())
    $currentBuild = [string](Get-ItemPropertyValue `
        -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
        -Name 'CurrentBuildNumber')
    Assert-True ($actualWindowsVersion -match '^Microsoft Windows NT 10\.0\.\d+\.0$' -and
        $actualWindowsVersion.Contains(".$currentBuild.")) `
        'Read the real Windows build with RtlGetVersion instead of the manifest-dependent Environment.OSVersion.'
    $sourceText = [IO.File]::ReadAllText($source)
    Assert-True ($sourceText.Contains('"SIDEY-PrerequisiteDownloads"') -and
        $sourceText.Contains('Directory.CreateDirectory(directory, security)') -and
        $sourceText.Contains('AssertDirectoryIsNotUserControlled') -and
        $sourceText.Contains('security.SetAccessRuleProtection(true, false);') -and
        -not $sourceText.Contains('GrantDesktopUserReadAccess')) `
        'Use an isolated ProgramData directory that is atomically protected and rejects unsafe precreation.'
    Assert-True ($sourceText.Contains('bool useDesktopUserRunner = requirement.RunAsDesktopUser;') -and
        -not $sourceText.Contains('DesktopUserIdentity.IsCurrentUser') -and
        $sourceText -match '(?s)private static int RunInstallerAsDesktopUser\(.*?if \(string\.IsNullOrWhiteSpace\(desktopUserRunner\)\)') `
        'Always route Windows App Runtime through the non-elevated desktop-user runner, including same-SID UAC elevation.'
    Assert-True ($sourceText.Contains('"VerifyIsOK"') -and
        $sourceText.Contains('"FindPackagesForUserWithPackageTypes"') -and
        $sourceText.Contains('1 | 2') -and
        $sourceText.Contains('DesktopUserIdentity.GetSecurityIdentifier()') -and
        -not $sourceText.Contains('ProvisionPackageForAllUsersAsync') -and
        -not $sourceText.Contains('FindPackagesByPackageFamily')) `
        'Query desktop-user Main and Framework packages and require Package.Status.VerifyIsOK.'
    $desktopUserSid = [string](Invoke-Static $desktopUser 'GetSecurityIdentifier' @())
    Assert-True (-not [string]::IsNullOrWhiteSpace($desktopUserSid)) `
        'Resolve the interactive desktop user security identifier.'
    Assert-True (-not (Invoke-Static $packageQuery 'HasPackage' `
        @('Sidey.Does.Not.Exist_8wekyb3d8bbwe', [version]'1.0.0.0', $desktopUserSid))) `
        'Reject an unregistered package family.'
    $installationType = [string](Get-ItemPropertyValue `
        -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
        -Name 'InstallationType')
    if ($installationType -ceq 'Client') {
        $knownGoodPackage = Get-AppxPackage -PackageTypeFilter Framework, Main | Where-Object {
            $_.Status -eq 'Ok' -and [string]$_.Architecture -eq 'X64' -and $_.PackageFullName
        } | Select-Object -First 1
        if ($null -eq $knownGoodPackage) { throw 'No usable package is available for the package status test.' }
        Assert-True (Invoke-Static $packageStatus 'IsUsable' @([string]$knownGoodPackage.PackageFullName)) `
            'Require Package.Status.VerifyIsOK before accepting an installed package.'
        Assert-True (Invoke-Static $packageQuery 'HasPackage' `
            @([string]$knownGoodPackage.PackageFamilyName, [version]$knownGoodPackage.Version, $desktopUserSid)) `
            'Find a usable desktop-user Main or Framework package through the compiled query path.'
    }
    else {
        Write-Host "Skipped client AppX reflection probe on Windows installation type: $installationType"
    }

    foreach ($url in @(
        'http://download.microsoft.com/runtime.exe',
        'https://download.microsoft.com.evil.example/runtime.exe',
        'https://example.com/runtime.exe',
        'https://aka.ms:444/runtime.exe',
        'https://user@aka.ms/runtime.exe')) {
        Assert-Throws { Invoke-Static $download 'ValidateUri' (,([uri]$url)) } 'Reject an untrusted download or redirect URL.'
    }
    foreach ($url in @(
        'https://aka.ms/runtime.exe',
        'https://builds.dotnet.microsoft.com/runtime.exe',
        'https://download.visualstudio.microsoft.com/runtime.exe',
        'https://download.microsoft.com/runtime.exe')) {
        Invoke-Static $download 'ValidateUri' (,([uri]$url)) | Out-Null
        $script:assertions++
    }
    Assert-True (Invoke-Static $signer 'IsMicrosoftCorporationSubject' `
        @('CN=.NET, O=Microsoft Corporation, L=Redmond, S=Washington, C=US')) `
        'Accept a Microsoft product signer organization.'
    foreach ($subject in @('', 'CN=Microsoft Corporation', 'CN=.NET, O=Not Microsoft Corporation, C=US',
        'CN=.NET, O=Microsoft Corporation Fake, C=US')) {
        Assert-True (-not (Invoke-Static $signer 'IsMicrosoftCorporationSubject' @($subject))) `
            'Reject a missing or non-Microsoft signer organization.'
    }
    Assert-Throws { Invoke-Static $signer 'AssertMicrosoftSignature' @($source) } `
        'Reject unsigned input bytes.'

    $retryDownloadDirectory = Join-Path $testRoot 'retry-download'
    [void][IO.Directory]::CreateDirectory($retryDownloadDirectory)
    $staleDownloadPath = Join-Path $retryDownloadDirectory 'component.exe'
    [IO.File]::WriteAllText($staleDownloadPath, 'partial prerequisite download')
    $preparedDownloadPath = [string](Invoke-Static $prerequisiteService 'SafeDownloadPath' `
        @($retryDownloadDirectory, 'component.exe'))
    Assert-True ($preparedDownloadPath -ceq $staleDownloadPath -and
        -not (Test-Path -LiteralPath $staleDownloadPath)) `
        'Remove an ordinary stale prerequisite download so Setup can retry.'

    [IO.File]::WriteAllText($staleDownloadPath, 'active prerequisite download')
    $activeDownload = [IO.File]::Open(
        $staleDownloadPath,
        [IO.FileMode]::Open,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None)
    try {
        Assert-Throws { Invoke-Static $prerequisiteService 'SafeDownloadPath' `
            @($retryDownloadDirectory, 'component.exe') } `
            'Do not delete a prerequisite download that another Setup still owns.'
        $cleanupWarnings = New-Object 'Collections.Generic.List[string]'
        $warningWriter = [Action[string]]{
            param([string]$warning)
            [void]$cleanupWarnings.Add($warning)
        }
        Invoke-Static $prerequisiteService 'TryDeleteDownloadFile' `
            @($staleDownloadPath, 'test component', $warningWriter) | Out-Null
        Assert-True ($cleanupWarnings.Count -eq 1 -and
            $cleanupWarnings[0].Contains('component=test component')) `
            'Report download cleanup failure without replacing the prerequisite result.'
    }
    finally {
        $activeDownload.Dispose()
    }
    Assert-True (Test-Path -LiteralPath $staleDownloadPath -PathType Leaf) `
        'Keep an active prerequisite download after rejecting concurrent cleanup.'
    Remove-Item -LiteralPath $staleDownloadPath -Force

    $loadedConfiguration = Invoke-Static $configType 'Load' @($configuration)
    Assert-True ($null -ne $loadedConfiguration) 'Load the shipped prerequisite configuration.'
    $requiredPackages = @((Get-Content -LiteralPath $configuration -Raw -Encoding UTF8 |
        ConvertFrom-Json).windowsAppRuntime.packages)
    $currentUserPackages = @(Get-AppxPackage -PackageTypeFilter Framework, Main -ErrorAction Stop)
    foreach ($requiredPackage in $requiredPackages) {
        $minimumVersion = [version]$requiredPackage.minimumVersion
        $expectedAvailable = @($currentUserPackages | Where-Object {
            $_.PackageFamilyName -ceq $requiredPackage.family -and
            [string]$_.Architecture -ceq 'X64' -and
            [version]$_.Version -ge $minimumVersion -and
            [string]$_.Status -ceq 'Ok'
        }).Count -gt 0
        $actualAvailable = Invoke-Static $packageQuery 'HasPackage' `
            @([string]$requiredPackage.family, $minimumVersion, $desktopUserSid)
        Assert-True ($actualAvailable -eq $expectedAvailable) `
            "Match current-user Main/Framework package inventory for $($requiredPackage.family)."
    }
    $invalidConfiguration = Join-Path $testRoot 'invalid.json'
    [IO.File]::WriteAllText($invalidConfiguration, '{"visualCpp":{}}', [Text.UTF8Encoding]::new($false))
    Assert-Throws { Invoke-Static $configType 'Load' @($invalidConfiguration) } 'Reject incomplete configuration.'

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
        @('5', 'PERMISSION_DENIED'), @('1300', 'PERMISSION_DENIED'),
        @('1314', 'PERMISSION_DENIED'),
        @('12002', 'NETWORK_ERROR'), @('12007', 'NETWORK_ERROR'), @('12029', 'NETWORK_ERROR'),
        @('12030', 'NETWORK_ERROR'), @('12031', 'NETWORK_ERROR'), @('12163', 'NETWORK_ERROR'),
        @('1602', 'USER_CANCELLED'), @('1603', 'UNKNOWN_ERROR'),
        @('1618', 'ANOTHER_INSTALLATION_RUNNING'), @('1619', 'PACKAGE_CORRUPTED'),
        @('1620', 'PACKAGE_CORRUPTED'), @('1625', 'BLOCKED_BY_POLICY'),
        @('1633', 'INCOMPATIBLE_SYSTEM'), @('1638', 'ALREADY_INSTALLED'))
    foreach ($mapping in $errorMappings) {
        $result = Invoke-Static $errors 'CreateResult' `
            @($mapping[0], 'TEST', 'INSTALL', $null, $null, $null, $null, $null, '1.3.1')
        Assert-True ((Get-Field $result 'Status') -ceq 'FAILED' -and
            (Get-Field $result 'Category') -ceq $mapping[1]) "Normalize $($mapping[0])."
    }
    Assert-True ((Invoke-Static $errors 'NormalizeNativeCode' @(-2147009281)) -ceq '0x80073CFF') `
        'Preserve signed HRESULT values as canonical hexadecimal.'
    foreach ($opaqueCode in @('128', '0x80070032', '0x80131500')) {
        $opaqueResult = Invoke-Static $errors 'CreateResult' `
            @($opaqueCode, 'TEST', 'INSTALL', $null, 'test component', $null, $opaqueCode, $null, '1.3.1')
        Assert-True ((Get-Field $opaqueResult 'Category') -ceq 'UNKNOWN_ERROR') `
            "Do not assign a misleading global meaning to opaque code $opaqueCode."
    }
    Assert-True (Invoke-Static $installPolicy 'IsAvailableAfterNonzeroExit' `
        @([int]128, [Func[bool]]{ return $true })) `
        'Accept an opaque installer exit such as 128 when the required runtime is usable.'
    Assert-True (-not (Invoke-Static $installPolicy 'IsAvailableAfterNonzeroExit' `
        @([int]128, [Func[bool]]{ return $false }))) `
        'Keep an opaque installer exit as a failure when the required runtime is unavailable.'
    Assert-Throws { Invoke-Static $installPolicy 'IsAvailableAfterNonzeroExit' `
        @([int]0, [Func[bool]]{ return $true }) } `
        'Apply postcondition recovery only to nonzero installer exits.'
    Assert-True (-not (Invoke-Static $installPolicy 'IsAvailableAfterSuccessfulExit' `
        @([Func[bool]]{ return $false }))) `
        'Preserve a missing prerequisite after an installer reports success.'
    Assert-Throws { Invoke-Static $installPolicy 'IsAvailableAfterSuccessfulExit' `
        @([Func[bool]]{ throw [InvalidOperationException]::new('postcondition failed') }) } `
        'Surface a throwing success postcondition so the caller can add component context.'

    $resultPath = Join-Path $testRoot 'Installer Result.ini'
    $logPath = Join-Path $testRoot 'SIDEY Setup.log'
    $process = Start-Helper @(
        '--normalize-error', '--native-code', '-2147009281', '--source', 'APPX', '--stage', 'INSTALL',
        '--target', 'Windows App Runtime x64', '--command-description', 'runtime install',
        '--exit-code', '-2147009281', '--result-path', $resultPath, '--log-path', $logPath,
        '--installer-version', '1.3.1')
    Assert-True ($process.ExitCode -eq 0) 'Normalization mode must succeed after writing the failure result.'
    $bytes = [IO.File]::ReadAllBytes($resultPath)
    Assert-True ($bytes.Length -ge 2 -and $bytes[0] -eq 0xff -and $bytes[1] -eq 0xfe) `
        'Write the NSIS handoff file as UTF-16 LE with a BOM.'
    $resultText = [IO.File]::ReadAllText($resultPath, [Text.Encoding]::Unicode)
    $logText = [IO.File]::ReadAllText($logPath, [Text.Encoding]::UTF8)
    Assert-True ($resultText.Contains('category=BLOCKED_BY_POLICY') -and
        $resultText.Contains('nativeCode=0x80073CFF')) 'Write normalized NSIS handoff fields.'
    Assert-True ($logText.Contains('source=APPX') -and $logText.Contains('installerVersion=1.3.1') -and
        $logText.Contains("windowsVersion=$actualWindowsVersion")) `
        'Append stable diagnostic log fields.'

    $installRoot = Join-Path $testRoot 'Install Root'
    $runtimeRoot = Join-Path $installRoot 'Runtime'
    $workingDirectory = Join-Path $runtimeRoot 'en-US'
    [void][IO.Directory]::CreateDirectory($workingDirectory)
    [IO.File]::WriteAllText((Join-Path $runtimeRoot 'legacy.dll'), 'legacy')
    [IO.File]::WriteAllText((Join-Path $installRoot 'SIDEY.exe'), 'launcher')
    $process = Start-Helper @(
        '--cleanup-private-runtime', '--install-directory', $installRoot,
        '--result-path', $resultPath, '--log-path', $logPath,
        '--installer-version', '1.3.1') $workingDirectory
    Assert-True ($process.ExitCode -eq 0 -and -not (Test-Path -LiteralPath $runtimeRoot)) `
        'Remove a legacy private Runtime even when inherited as the native working directory.'
    Assert-True (Test-Path -LiteralPath (Join-Path $installRoot 'SIDEY.exe')) `
        'Preserve files outside the private Runtime.'

    $sharedRoot = Join-Path $testRoot 'Shared Runtime'
    [void][IO.Directory]::CreateDirectory($sharedRoot)
    [IO.File]::WriteAllText((Join-Path $sharedRoot 'shared.dll'), 'shared')
    New-Item -ItemType Junction -Path $runtimeRoot -Target $sharedRoot | Out-Null
    try {
        $process = Start-Helper @(
            '--cleanup-private-runtime', '--install-directory', $installRoot,
            '--result-path', $resultPath, '--log-path', $logPath,
            '--installer-version', '1.3.1')
        Assert-True ($process.ExitCode -eq 1) 'Reject a Runtime junction.'
        Assert-True (Test-Path -LiteralPath (Join-Path $sharedRoot 'shared.dll')) `
            'Never follow a Runtime junction into a shared directory.'
    }
    finally {
        [IO.Directory]::Delete($runtimeRoot)
    }

    $process = Start-Helper @('--sidey-invalid-argument')
    Assert-True ($process.ExitCode -eq 64) 'Reject unsupported CLI arguments.'
}
finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ([IO.Directory]::GetParent($resolvedTestRoot).FullName -cne $expectedParent -or
        [IO.Path]::GetFileName($resolvedTestRoot) -notlike 'SIDEY prerequisite helper tests *') {
        throw 'Unsafe prerequisite helper test cleanup path.'
    }
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}

Write-Host "PrerequisiteInstallerTests=true; Assertions=$script:assertions"
