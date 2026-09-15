#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$transactionScript = Join-Path $root 'windows/installer/Sidey.Setup/InstallTransaction.ps1'
$probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('SIDEY install transaction ' + [Guid]::NewGuid().ToString('N'))
$install = Join-Path $probeRoot 'SIDEY'
$staging = $install + '.sidey-staging-1234'
$rollback = $install + '.sidey-rollback'
$version = '9.8.7'
$assertions = 0

function Assert-True([bool]$Condition, [string]$Message) {
    $script:assertions++
    if (-not $Condition) { throw $Message }
}

function Invoke-Transaction([string]$Action) {
    & $transactionScript -Action $Action -InstallDirectory $install `
        -StagingDirectory $staging -RollbackDirectory $rollback -Version $version `
        -AllowUserWritableParentForTests
}

function New-Payload([string]$Marker) {
    [IO.Directory]::CreateDirectory((Join-Path $staging 'Runtime')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $staging 'SIDEY.exe'), $Marker)
    [IO.File]::WriteAllText((Join-Path $staging 'Runtime/SIDEY.Host.exe'), $Marker)
    [IO.File]::WriteAllText((Join-Path $staging 'Runtime/SIDEY.UninstallHelper.exe'), $Marker)
    [IO.File]::WriteAllText((Join-Path $staging 'Uninstall.exe'), $Marker)
}

try {
    [IO.Directory]::CreateDirectory($probeRoot) | Out-Null
    [IO.Directory]::CreateDirectory($install) | Out-Null
    [IO.File]::WriteAllText((Join-Path $install 'marker.txt'), 'old')

    Invoke-Transaction Prepare
    New-Payload 'new'
    Invoke-Transaction Activate
    Assert-True ((Get-Content -LiteralPath (Join-Path $install 'SIDEY.exe') -Raw) -ceq 'new') `
        'Activate did not promote the staged payload.'
    Assert-True ([IO.File]::Exists((Join-Path $rollback 'marker.txt'))) `
        'Activate did not retain the previous install for rollback.'
    Invoke-Transaction Rollback
    Assert-True ((Get-Content -LiteralPath (Join-Path $install 'marker.txt') -Raw) -ceq 'old') `
        'Rollback did not restore the previous install.'
    Assert-True (-not [IO.Directory]::Exists($rollback)) `
        'Rollback left its backup directory behind.'

    $rolledBackState = [ordered]@{
        schemaVersion = 1
        phase = 'rolled-back'
        version = $version
        installDirectory = $install
        stagingDirectory = $staging
        rollbackDirectory = $rollback
        previousInstallExisted = $true
        previousRegistration = [ordered]@{ managed = $false }
    }
    [IO.File]::WriteAllText(
        ($install + '.sidey-transaction.json'),
        ($rolledBackState | ConvertTo-Json -Compress),
        [Text.UTF8Encoding]::new($false))
    Invoke-Transaction Prepare
    Assert-True ((Get-Content -LiteralPath (Join-Path $install 'marker.txt') -Raw) -ceq 'old') `
        'A stale rolled-back marker removed the restored live installation.'
    Invoke-Transaction Rollback

    Invoke-Transaction Prepare
    New-Payload 'new-committed'
    Invoke-Transaction Activate
    Invoke-Transaction BeginRegistration
    Invoke-Transaction Commit
    Invoke-Transaction Complete
    Assert-True ((Get-Content -LiteralPath (Join-Path $install 'SIDEY.exe') -Raw) -ceq 'new-committed') `
        'Complete did not keep the committed payload.'
    Assert-True (-not [IO.Directory]::Exists($rollback)) `
        'Complete did not remove the previous install.'
    Assert-True (-not [IO.File]::Exists($install + '.sidey-transaction.json')) `
        'Complete did not remove transaction state.'

    Remove-Item -LiteralPath $install -Recurse -Force
    Invoke-Transaction Prepare
    New-Payload 'fresh-registering'
    Invoke-Transaction Activate
    Invoke-Transaction BeginRegistration
    Invoke-Transaction Rollback
    Assert-True (-not [IO.Directory]::Exists($install)) `
        'Registration rollback left a fresh payload orphaned.'
    [IO.Directory]::CreateDirectory($install) | Out-Null
    [IO.File]::WriteAllText((Join-Path $install 'SIDEY.exe'), 'restored-test-baseline')

    Invoke-Transaction Prepare
    [IO.File]::WriteAllText((Join-Path $staging 'partial.txt'), 'partial')
    Invoke-Transaction Prepare
    Assert-True ([IO.File]::Exists((Join-Path $install 'SIDEY.exe'))) `
        'Recovering an interrupted staging pass removed the live install.'
    Assert-True (-not [IO.File]::Exists((Join-Path $staging 'partial.txt'))) `
        'Prepare did not discard an interrupted partial staging payload.'

    Remove-Item -LiteralPath $staging -Recurse -Force
    Remove-Item -LiteralPath ($install + '.sidey-transaction.json') -Force
    Remove-Item -LiteralPath $install -Recurse -Force
    [IO.Directory]::CreateDirectory($install) | Out-Null
    [IO.File]::WriteAllText((Join-Path $install 'marker.txt'), 'interrupted-old')
    Invoke-Transaction Prepare
    New-Payload 'interrupted-new'
    Invoke-Transaction Activate
    Invoke-Transaction Prepare
    Assert-True ((Get-Content -LiteralPath (Join-Path $install 'marker.txt') -Raw) -ceq 'interrupted-old') `
        'Prepare did not recover an uncommitted interrupted activation.'
    Assert-True ([IO.Directory]::Exists($staging)) `
        'Prepare did not create a clean staging directory after recovery.'

    Remove-Item -LiteralPath $staging -Recurse -Force
    New-Payload 'pending-cleanup-new'
    Invoke-Transaction Activate
    Invoke-Transaction BeginRegistration
    Invoke-Transaction Commit
    Invoke-Transaction Prepare
    Assert-True ((Get-Content -LiteralPath (Join-Path $install 'SIDEY.exe') -Raw) -ceq 'pending-cleanup-new') `
        'Prepare discarded a committed payload awaiting cleanup.'
    Assert-True (-not [IO.Directory]::Exists($rollback)) `
        'Prepare did not finish cleanup for a committed transaction.'

    Remove-Item -LiteralPath $staging -Recurse -Force
    New-Payload 'uninstall-cleanup-new'
    Invoke-Transaction Activate
    Invoke-Transaction BeginRegistration
    Invoke-Transaction Commit
    Invoke-Transaction CleanupForUninstall
    Assert-True ([IO.File]::Exists((Join-Path $install 'SIDEY.exe'))) `
        'Uninstall cleanup removed the committed live payload.'
    Assert-True (-not [IO.Directory]::Exists($rollback)) `
        'Uninstall cleanup left the previous-version backup behind.'
    Assert-True (-not [IO.File]::Exists($install + '.sidey-transaction.json')) `
        'Uninstall cleanup left transaction state behind.'

    Invoke-Transaction Prepare
    New-Payload 'committed-before-uninstall'
    Invoke-Transaction Activate
    Invoke-Transaction BeginRegistration
    Invoke-Transaction Commit
    Remove-Item -LiteralPath $install -Recurse -Force
    Invoke-Transaction Prepare
    Assert-True ((Get-Content -LiteralPath (Join-Path $install 'SIDEY.exe') -Raw) -ceq 'uninstall-cleanup-new') `
        'Prepare did not restore the last known-good backup when committed live was missing.'
    Assert-True (-not [IO.Directory]::Exists($rollback)) `
        'Prepare retained the backup after restoring a missing committed live install.'
    Assert-True ([IO.Directory]::Exists($staging)) `
        'Prepare did not start a clean transaction after committed-install removal.'
    New-Payload 'replacement-after-uninstall'
    Invoke-Transaction Activate
    Invoke-Transaction BeginRegistration
    Invoke-Transaction Commit
    Invoke-Transaction Complete

    Invoke-Transaction Prepare
    [IO.File]::WriteAllText((Join-Path $staging 'SIDEY.exe'), 'incomplete')
    $failed = $false
    try { Invoke-Transaction Activate } catch { $failed = $true }
    Assert-True $failed 'Activate accepted an incomplete staged payload.'
    Assert-True ([IO.File]::Exists((Join-Path $install 'SIDEY.exe'))) `
        'An incomplete staged payload changed the live install.'
    Invoke-Transaction Rollback

    $unsafeFailed = $false
    try {
        & $transactionScript -Action Prepare -InstallDirectory $install `
            -StagingDirectory (Join-Path $probeRoot 'not-a-sidey-stage') `
            -RollbackDirectory $rollback -Version $version -AllowUserWritableParentForTests
    }
    catch { $unsafeFailed = $true }
    Assert-True $unsafeFailed 'The transaction accepted an unrelated staging directory.'

    Write-Host "Install transaction tests passed. Assertions=$assertions"
}
finally {
    if ([IO.Directory]::Exists($probeRoot)) {
        Remove-Item -LiteralPath $probeRoot -Recurse -Force
    }
}
