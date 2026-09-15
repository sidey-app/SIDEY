#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Recover', 'Prepare', 'Activate', 'BeginRegistration', 'Commit', 'Rollback', 'Complete', 'CleanupForUninstall')]
    [string]$Action,

    [Parameter(Mandatory = $true)][string]$InstallDirectory,
    [Parameter(Mandatory = $true)][string]$StagingDirectory,
    [Parameter(Mandatory = $true)][string]$RollbackDirectory,
    [Parameter(Mandatory = $true)][string]$Version,

    [switch]$AllowUserWritableParentForTests
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Get-NormalizedPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
}

$installPath = Get-NormalizedPath $InstallDirectory
$stagingPath = Get-NormalizedPath $StagingDirectory
$rollbackPath = Get-NormalizedPath $RollbackDirectory
$parentPath = [IO.Directory]::GetParent($installPath)
if ($null -eq $parentPath -or $installPath -ceq $parentPath.Root.FullName.TrimEnd('\')) {
    throw 'The SIDEY install directory cannot be a drive root.'
}
$parentPath = Get-NormalizedPath $parentPath.FullName
$expectedStagingPrefix = $installPath + '.sidey-staging-'
$expectedRollbackPath = $installPath + '.sidey-rollback'
$statePath = $installPath + '.sidey-transaction.json'
$transactionRegistryPath = 'Software\SIDEY\InstallerTransaction'
$script:previousRegistration = $null
$script:previousInstallExisted = $false
$script:transactionStagingPath = $stagingPath

if (-not $stagingPath.StartsWith($expectedStagingPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    (Get-NormalizedPath ([IO.Directory]::GetParent($stagingPath).FullName)) -ine $parentPath) {
    throw 'The SIDEY staging directory must be a reserved sibling of the install directory.'
}
if ($rollbackPath -ine $expectedRollbackPath -or
    (Get-NormalizedPath ([IO.Directory]::GetParent($rollbackPath).FullName)) -ine $parentPath) {
    throw 'The SIDEY rollback directory must be the reserved sibling of the install directory.'
}

function Assert-StagingDirectoryPath([string]$Path) {
    $normalized = Get-NormalizedPath $Path
    $parent = [IO.Directory]::GetParent($normalized)
    if (-not $normalized.StartsWith($expectedStagingPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        $null -eq $parent -or (Get-NormalizedPath $parent.FullName) -ine $parentPath) {
        throw 'The SIDEY transaction state contains an unsafe staging directory.'
    }
    return $normalized
}

function Assert-OrdinaryDirectory([string]$Path) {
    if (-not [IO.Directory]::Exists($Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to use a reparse point for the SIDEY install transaction: $Path"
    }
}

function Assert-NoReparseAncestors([string]$Path) {
    $current = [IO.DirectoryInfo]::new($Path)
    while ($null -ne $current) {
        if ($current.Exists -and
            ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing a reparse-point ancestor for the SIDEY install transaction: $($current.FullName)"
        }
        $current = $current.Parent
    }
}

function Assert-NoReparseTree([string]$Path) {
    if (-not [IO.Directory]::Exists($Path)) { return }
    $pending = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
    $pending.Push([IO.DirectoryInfo]::new($Path))
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing a reparse point in the SIDEY install transaction: $($directory.FullName)"
        }
        foreach ($item in $directory.EnumerateFileSystemInfos()) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing a reparse point in the SIDEY install transaction: $($item.FullName)"
            }
            if ($item -is [IO.DirectoryInfo]) {
                $pending.Push($item)
            }
        }
    }
}

function Assert-SecureTransactionParent {
    Assert-NoReparseAncestors $parentPath
    if ($AllowUserWritableParentForTests) { return }

    $administrators = 'S-1-5-32-544'
    $system = 'S-1-5-18'
    $trustedInstaller = 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
    $creatorOwner = 'S-1-3-0'
    $privilegedSids = @($administrators, $system, $trustedInstaller)
    $acl = Get-Acl -LiteralPath $parentPath
    $ownerSid = ([Security.Principal.NTAccount]$acl.Owner).Translate(
        [Security.Principal.SecurityIdentifier]).Value
    if ($privilegedSids -notcontains $ownerSid) {
        throw 'The SIDEY install directory parent must be owned by Administrators, SYSTEM, or TrustedInstaller.'
    }

    $writeRights = [Security.AccessControl.FileSystemRights]::Write -bor
        [Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [Security.AccessControl.FileSystemRights]::TakeOwnership
    foreach ($rule in $acl.GetAccessRules(
        $true,
        $true,
        [Security.Principal.SecurityIdentifier])) {
        $rawRights = [uint32]([int64]$rule.FileSystemRights -band 0xffffffffL)
        $hasGenericWrite = ($rawRights -band 0x50000000) -ne 0
        $isSafeCreatorOwnerInheritance =
            $rule.IdentityReference.Value -eq $creatorOwner -and
            ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -ne 0
        if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
            -not $isSafeCreatorOwnerInheritance -and
            (($rule.FileSystemRights -band $writeRights) -ne 0 -or $hasGenericWrite) -and
            $privilegedSids -notcontains $rule.IdentityReference.Value) {
            throw "The SIDEY install directory parent is writable by an unprivileged identity: $($rule.IdentityReference.Value)"
        }
    }
}

function Protect-StagingDirectory {
    if ($AllowUserWritableParentForTests) { return }
    $administrators = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $system = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $users = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $propagation = [Security.AccessControl.PropagationFlags]::None
    $allow = [Security.AccessControl.AccessControlType]::Allow
    $security = [Security.AccessControl.DirectorySecurity]::new()
    $security.SetAccessRuleProtection($true, $false)
    $security.SetOwner($administrators)
    $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        $administrators,
        [Security.AccessControl.FileSystemRights]::FullControl,
        $inheritance,
        $propagation,
        $allow))
    $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        $system,
        [Security.AccessControl.FileSystemRights]::FullControl,
        $inheritance,
        $propagation,
        $allow))
    $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        $users,
        [Security.AccessControl.FileSystemRights]::ReadAndExecute,
        $inheritance,
        $propagation,
        $allow))
    [IO.Directory]::SetAccessControl($stagingPath, $security)
}

function Set-PendingInstallLocation {
    if ($AllowUserWritableParentForTests) { return }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $key = $base.CreateSubKey($transactionRegistryPath)
        try {
            $key.SetValue(
                'InstallLocation',
                $installPath,
                [Microsoft.Win32.RegistryValueKind]::String)
        }
        finally {
            $key.Dispose()
        }
    }
    finally {
        $base.Dispose()
    }
}

function Clear-PendingInstallLocation {
    if ($AllowUserWritableParentForTests) { return }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $base.DeleteSubKeyTree($transactionRegistryPath, $false)
    }
    finally {
        $base.Dispose()
    }
}

function Get-PreviousRegistration {
    if ($AllowUserWritableParentForTests) {
        return [ordered]@{ managed = $false }
    }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $key = $base.OpenSubKey('Software\SIDEY\Installer')
        try {
            $previousVersion = if ($null -eq $key) { $null } else { $key.GetValue('InstalledVersion', $null) }
            return [ordered]@{
                managed = $true
                existed = $null -ne $previousVersion
                version = [string]$previousVersion
                language = if ($null -eq $key) { '' } else { [string]$key.GetValue('Language', '') }
                location = if ($null -eq $key) { $installPath } else { [string]$key.GetValue('InstallLocation', $installPath) }
            }
        }
        finally {
            if ($null -ne $key) { $key.Dispose() }
        }
    }
    finally {
        $base.Dispose()
    }
}

function Restore-PreviousRegistration {
    if ($null -eq $script:previousRegistration -or
        -not [bool]$script:previousRegistration.managed) {
        return
    }

    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    try {
        foreach ($keyPath in @(
            'Software\SIDEY\Installer',
            'Software\Microsoft\Windows\CurrentVersion\Uninstall\SIDEY',
            'Software\Classes\sidey')) {
            $base.DeleteSubKeyTree($keyPath, $false)
        }

        $startMenu = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'SIDEY'
        if ([IO.Directory]::Exists($startMenu)) {
            Remove-TransactionDirectory $startMenu
        }
        if (-not [bool]$script:previousRegistration.existed) { return }

        $location = [string]$script:previousRegistration.location
        $version = [string]$script:previousRegistration.version
        $language = [string]$script:previousRegistration.language
        $installer = $base.CreateSubKey('Software\SIDEY\Installer')
        $uninstall = $base.CreateSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall\SIDEY')
        $protocol = $base.CreateSubKey('Software\Classes\sidey')
        try {
            if (-not [string]::IsNullOrWhiteSpace($language)) {
                $installer.SetValue('Language', $language, [Microsoft.Win32.RegistryValueKind]::String)
            }
            $installer.SetValue('InstallLocation', $location, [Microsoft.Win32.RegistryValueKind]::String)
            $installer.SetValue('InstalledVersion', $version, [Microsoft.Win32.RegistryValueKind]::String)
            $uninstall.SetValue('DisplayName', 'SIDEY', [Microsoft.Win32.RegistryValueKind]::String)
            $uninstall.SetValue('Publisher', 'SIDEY', [Microsoft.Win32.RegistryValueKind]::String)
            $uninstall.SetValue('InstallLocation', $location, [Microsoft.Win32.RegistryValueKind]::String)
            $uninstall.SetValue('DisplayIcon', (Join-Path $location 'Assets\Icons\SideyAppIcon.ico'), [Microsoft.Win32.RegistryValueKind]::String)
            $uninstall.SetValue('UninstallString', ('"' + (Join-Path $location 'Uninstall.exe') + '"'), [Microsoft.Win32.RegistryValueKind]::String)
            $uninstall.SetValue('QuietUninstallString', ('"' + (Join-Path $location 'Uninstall.exe') + '" /S'), [Microsoft.Win32.RegistryValueKind]::String)
            $uninstall.SetValue('NoModify', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
            $uninstall.SetValue('NoRepair', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
            $uninstall.SetValue('DisplayVersion', $version, [Microsoft.Win32.RegistryValueKind]::String)
            $protocol.SetValue('', 'URL:SIDEY authentication callback', [Microsoft.Win32.RegistryValueKind]::String)
            $protocol.SetValue('URL Protocol', '', [Microsoft.Win32.RegistryValueKind]::String)
            $protocol.CreateSubKey('DefaultIcon').SetValue('', (Join-Path $location 'Assets\Icons\SideyAppIcon.ico'))
            $protocol.CreateSubKey('shell\open\command').SetValue(
                '',
                ('"' + (Join-Path $location 'SIDEY.exe') + '" "%1"'))
        }
        finally {
            $installer.Dispose()
            $uninstall.Dispose()
            $protocol.Dispose()
        }

        [IO.Directory]::CreateDirectory($startMenu) | Out-Null
        $shell = New-Object -ComObject WScript.Shell
        foreach ($shortcutSpec in @(
            @('SIDEY.lnk', (Join-Path $location 'SIDEY.exe')),
            @('Uninstall SIDEY.lnk', (Join-Path $location 'Uninstall.exe')))) {
            $shortcut = $shell.CreateShortcut((Join-Path $startMenu $shortcutSpec[0]))
            $shortcut.TargetPath = $shortcutSpec[1]
            $shortcut.IconLocation = Join-Path $location 'Assets\Icons\SideyAppIcon.ico'
            $shortcut.Save()
        }
    }
    finally {
        $base.Dispose()
    }
}

function Remove-TransactionDirectory([string]$Path) {
    if (-not [IO.Directory]::Exists($Path)) { return }
    Assert-NoReparseTree $Path
    Remove-Item -LiteralPath $Path -Recurse -Force
}

function Write-State([string]$Phase) {
    $temporaryPath = $statePath + '.tmp'
    foreach ($path in @($statePath, $temporaryPath)) {
        if ([IO.File]::Exists($path)) {
            $item = Get-Item -LiteralPath $path -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Refusing a reparse point for SIDEY transaction state.'
            }
        }
    }
    $state = [ordered]@{
        schemaVersion = 1
        phase = $Phase
        version = $Version
        installDirectory = $installPath
        stagingDirectory = $script:transactionStagingPath
        rollbackDirectory = $rollbackPath
        previousInstallExisted = $script:previousInstallExisted
        previousRegistration = $script:previousRegistration
    }
    [IO.File]::WriteAllText(
        $temporaryPath,
        ($state | ConvertTo-Json -Compress),
        [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $statePath -Force
}

function Read-State {
    if (-not [IO.File]::Exists($statePath)) { return $null }
    $stateItem = Get-Item -LiteralPath $statePath -Force
    if (($stateItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Refusing to use a reparse point for SIDEY transaction state.'
    }
    $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.schemaVersion -ne 1 -or
        (Get-NormalizedPath ([string]$state.installDirectory)) -ine $installPath -or
        (Get-NormalizedPath ([string]$state.rollbackDirectory)) -ine $rollbackPath) {
        throw 'The SIDEY install transaction state is invalid.'
    }
    [void](Assert-StagingDirectoryPath ([string]$state.stagingDirectory))
    $script:transactionStagingPath = Get-NormalizedPath ([string]$state.stagingDirectory)
    if ($null -ne $state.PSObject.Properties['previousRegistration']) {
        $script:previousRegistration = $state.previousRegistration
    }
    if ($null -ne $state.PSObject.Properties['previousInstallExisted']) {
        $script:previousInstallExisted = [bool]$state.previousInstallExisted
    }
    return $state
}

function Remove-State {
    foreach ($path in @($statePath, ($statePath + '.tmp'))) {
        if (-not [IO.File]::Exists($path)) { continue }
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Refusing a reparse point while removing SIDEY transaction state.'
        }
        Remove-Item -LiteralPath $path -Force
    }
}

function Undo-Transaction($State) {
    $stagingToRemove = Assert-StagingDirectoryPath ([string]$State.stagingDirectory)
    $startingPhase = [string]$State.phase
    if ($startingPhase -eq 'rolled-back') {
        Remove-TransactionDirectory $rollbackPath
        Remove-TransactionDirectory $stagingToRemove
        if ($stagingToRemove -ine $stagingPath) {
            Remove-TransactionDirectory $stagingPath
        }
        Remove-State
        Clear-PendingInstallLocation
        return
    }
    if ($startingPhase -ne 'rolling-back') {
        Write-State 'rolling-back'
    }
    Assert-OrdinaryDirectory $rollbackPath
    if ([IO.Directory]::Exists($rollbackPath)) {
        if ([IO.Directory]::Exists($installPath)) {
            Remove-TransactionDirectory $installPath
        }
        Move-Item -LiteralPath $rollbackPath -Destination $installPath
    }
    elseif ($script:previousInstallExisted -and
        $startingPhase -ne 'staging' -and
        $startingPhase -ne 'prepared' -and
        $startingPhase -ne 'rolling-back') {
        throw 'The SIDEY rollback directory is missing for the previous installation.'
    }
    elseif (-not $script:previousInstallExisted -and
        ($startingPhase -eq 'activating' -or $startingPhase -eq 'active' -or
        $startingPhase -eq 'registering' -or $startingPhase -eq 'committed' -or
        $startingPhase -eq 'rolling-back')) {
        # A fresh install has no previous live directory to restore.
        Remove-TransactionDirectory $installPath
    }
    Remove-TransactionDirectory $stagingToRemove
    if ($stagingToRemove -ine $stagingPath) {
        Remove-TransactionDirectory $stagingPath
    }
    if ($startingPhase -eq 'registering' -or $startingPhase -eq 'committed' -or
        $startingPhase -eq 'rolling-back') {
        Restore-PreviousRegistration
    }
    Write-State 'rolled-back'
    Remove-State
    Clear-PendingInstallLocation
}

function Recover-InterruptedTransaction {
    $state = Read-State
    if ($null -eq $state) {
        if ([IO.Directory]::Exists($rollbackPath)) {
            throw 'An unrecognized SIDEY rollback directory already exists.'
        }
        Remove-TransactionDirectory $stagingPath
        return
    }

    if ([string]$state.phase -eq 'committed') {
        $recordedStaging = Assert-StagingDirectoryPath ([string]$state.stagingDirectory)
        if (-not [IO.Directory]::Exists($installPath)) {
            # Normal uninstall clears committed transaction residue before
            # deleting live. Missing live here is an interrupted/corrupt state,
            # so prefer the last known-good backup when one exists.
            Undo-Transaction $state
            return
        }
        Remove-TransactionDirectory $rollbackPath
        Remove-TransactionDirectory $recordedStaging
        Remove-State
        return
    }

    Undo-Transaction $state
}

switch ($Action) {
    'Recover' {
        Assert-SecureTransactionParent
        Recover-InterruptedTransaction
        Clear-PendingInstallLocation
    }
    'Prepare' {
        Assert-SecureTransactionParent
        Recover-InterruptedTransaction
        $script:transactionStagingPath = $stagingPath
        $script:previousInstallExisted = [IO.Directory]::Exists($installPath)
        $script:previousRegistration = Get-PreviousRegistration
        Set-PendingInstallLocation
        Write-State 'staging'
        [IO.Directory]::CreateDirectory($stagingPath) | Out-Null
        Protect-StagingDirectory
    }
    'Activate' {
        $state = Read-State
        if ($null -eq $state -or [string]$state.phase -ne 'staging' -or
            (Get-NormalizedPath ([string]$state.stagingDirectory)) -ine $stagingPath) {
            throw 'The SIDEY staging transaction is not ready to activate.'
        }
        foreach ($requiredPath in @(
            (Join-Path $stagingPath 'SIDEY.exe'),
            (Join-Path $stagingPath 'Runtime\SIDEY.Host.exe'),
            (Join-Path $stagingPath 'Runtime\SIDEY.UninstallHelper.exe'),
            (Join-Path $stagingPath 'Uninstall.exe'))) {
            if (-not [IO.File]::Exists($requiredPath)) {
                throw "The staged SIDEY payload is incomplete: $requiredPath"
            }
        }

        Assert-NoReparseTree $stagingPath
        Assert-OrdinaryDirectory $installPath
        if ([IO.Directory]::Exists($rollbackPath)) {
            throw 'The SIDEY rollback directory was not cleared before activation.'
        }

        Write-State 'prepared'
        try {
            if ([IO.Directory]::Exists($installPath)) {
                Move-Item -LiteralPath $installPath -Destination $rollbackPath
                Write-State 'previous-moved'
            }
            Write-State 'activating'
            Move-Item -LiteralPath $stagingPath -Destination $installPath
            Write-State 'active'
        }
        catch {
            $failedState = Read-State
            if ($null -ne $failedState) {
                Undo-Transaction $failedState
            }
            throw
        }
    }
    'Commit' {
        $state = Read-State
        if ($null -eq $state -or [string]$state.phase -ne 'registering' -or
            -not [IO.File]::Exists((Join-Path $installPath 'SIDEY.exe'))) {
            throw 'The SIDEY install transaction is not ready to commit.'
        }
        Write-State 'committed'
    }
    'BeginRegistration' {
        $state = Read-State
        if ($null -eq $state -or [string]$state.phase -ne 'active' -or
            -not [IO.File]::Exists((Join-Path $installPath 'SIDEY.exe'))) {
            throw 'The SIDEY install transaction is not ready to register.'
        }
        Write-State 'registering'
    }
    'Rollback' {
        $state = Read-State
        if ($null -ne $state) {
            Undo-Transaction $state
        }
        else {
            Remove-TransactionDirectory $stagingPath
            Clear-PendingInstallLocation
        }
    }
    'Complete' {
        $state = Read-State
        if ($null -eq $state -or [string]$state.phase -ne 'committed') {
            throw 'The SIDEY install transaction was not committed.'
        }
        # Cleanup is retryable. A locked backup does not invalidate the newly
        # registered live installation; the next Setup run will retry it.
        try {
            Remove-TransactionDirectory $rollbackPath
            Remove-TransactionDirectory (
                Assert-StagingDirectoryPath ([string]$state.stagingDirectory))
            Remove-State
            Clear-PendingInstallLocation
        }
        catch {
            Write-Warning $_.Exception.Message
            exit 10
        }
    }
    'CleanupForUninstall' {
        Assert-SecureTransactionParent
        $state = Read-State
        if ($null -ne $state) {
            if ([string]$state.phase -eq 'committed') {
                Remove-TransactionDirectory $rollbackPath
                Remove-TransactionDirectory (
                    Assert-StagingDirectoryPath ([string]$state.stagingDirectory))
                Remove-State
                Clear-PendingInstallLocation
            }
            else {
                Undo-Transaction $state
            }
        }
        else {
            Remove-TransactionDirectory $rollbackPath
            Remove-TransactionDirectory $stagingPath
            Clear-PendingInstallLocation
        }
    }
}
