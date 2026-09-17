#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PublishedApplicationSmoke.psm1') -Force

$startedAt = [DateTimeOffset]::Parse('2026-01-01T00:00:00Z')
$state = New-SideyStartupSmokeTimeoutState `
    -StartedAt $startedAt `
    -InactivityTimeoutSeconds 5 `
    -OverallTimeoutSeconds 20
if ($null -ne (Get-SideyStartupSmokeTimeoutReason `
        -State $state -ObservedAt $startedAt.AddMilliseconds(4999))) {
    throw 'Startup smoke timed out before its inactivity deadline.'
}
if ((Get-SideyStartupSmokeTimeoutReason `
        -State $state -ObservedAt $startedAt.AddSeconds(5)) -cne 'NoProgress') {
    throw 'Startup smoke did not stop at its inactivity deadline.'
}

$state = Update-SideyStartupSmokeTimeoutState `
    -State $state `
    -ObservedAt $startedAt.AddSeconds(4)
if ($null -ne (Get-SideyStartupSmokeTimeoutReason `
        -State $state -ObservedAt $startedAt.AddMilliseconds(8999))) {
    throw 'Startup smoke progress did not extend its inactivity deadline.'
}
if ((Get-SideyStartupSmokeTimeoutReason `
        -State $state -ObservedAt $startedAt.AddSeconds(9)) -cne 'NoProgress') {
    throw 'Startup smoke did not stop after progress ceased.'
}

$state = Update-SideyStartupSmokeTimeoutState `
    -State $state `
    -ObservedAt $startedAt.AddSeconds(19)
if ((Get-SideyStartupSmokeTimeoutReason `
        -State $state -ObservedAt $startedAt.AddSeconds(20)) -cne 'Overall') {
    throw 'Startup smoke progress exceeded its overall deadline.'
}

$simultaneousState = New-SideyStartupSmokeTimeoutState `
    -StartedAt $startedAt `
    -InactivityTimeoutSeconds 20 `
    -OverallTimeoutSeconds 20
if ((Get-SideyStartupSmokeTimeoutReason `
        -State $simultaneousState -ObservedAt $startedAt.AddSeconds(20)) -cne 'Overall') {
    throw 'The startup smoke overall deadline did not take precedence.'
}

$beforeDeadline = Resolve-SideyStartupSmokeObservation `
    -State (New-SideyStartupSmokeTimeoutState `
        -StartedAt $startedAt `
        -InactivityTimeoutSeconds 5 `
        -OverallTimeoutSeconds 20) `
    -ObservedAt $startedAt.AddMilliseconds(4999) `
    -HasProgress `
    -HasCompleted
if ($null -ne $beforeDeadline.TimeoutReason -or -not $beforeDeadline.Ready) {
    throw 'Startup smoke rejected completion observed before its deadline.'
}

$atInactivityDeadline = Resolve-SideyStartupSmokeObservation `
    -State (New-SideyStartupSmokeTimeoutState `
        -StartedAt $startedAt `
        -InactivityTimeoutSeconds 5 `
        -OverallTimeoutSeconds 20) `
    -ObservedAt $startedAt.AddSeconds(5) `
    -HasProgress `
    -HasCompleted
if ($atInactivityDeadline.TimeoutReason -cne 'NoProgress' -or $atInactivityDeadline.Ready) {
    throw 'Startup smoke accepted progress or completion at its inactivity deadline.'
}

$atOverallDeadline = Resolve-SideyStartupSmokeObservation `
    -State (New-SideyStartupSmokeTimeoutState `
        -StartedAt $startedAt `
        -InactivityTimeoutSeconds 20 `
        -OverallTimeoutSeconds 20) `
    -ObservedAt $startedAt.AddSeconds(20) `
    -HasProgress `
    -HasCompleted
if ($atOverallDeadline.TimeoutReason -cne 'Overall' -or $atOverallDeadline.Ready) {
    throw 'Startup smoke accepted progress or completion at its overall deadline.'
}

$invalidInactivity = $null
try {
    New-SideyStartupSmokeTimeoutState `
        -StartedAt $startedAt `
        -InactivityTimeoutSeconds 4 `
        -OverallTimeoutSeconds 20 | Out-Null
}
catch {
    $invalidInactivity = $_.Exception.Message
}
if ($invalidInactivity -cne 'Startup smoke inactivity timeout must be between 5 and 120 seconds.') {
    throw "Unexpected inactivity timeout validation: $invalidInactivity"
}

$invalidInactivityUpperBound = $null
try {
    New-SideyStartupSmokeTimeoutState `
        -StartedAt $startedAt `
        -InactivityTimeoutSeconds 121 `
        -OverallTimeoutSeconds 300 | Out-Null
}
catch {
    $invalidInactivityUpperBound = $_.Exception.Message
}
if ($invalidInactivityUpperBound -cne 'Startup smoke inactivity timeout must be between 5 and 120 seconds.') {
    throw "Unexpected inactivity timeout upper-bound validation: $invalidInactivityUpperBound"
}

$invalidOverall = $null
try {
    New-SideyStartupSmokeTimeoutState `
        -StartedAt $startedAt `
        -InactivityTimeoutSeconds 30 `
        -OverallTimeoutSeconds 29 | Out-Null
}
catch {
    $invalidOverall = $_.Exception.Message
}
if ($invalidOverall -cne 'Startup smoke overall timeout must be between 30 and 600 seconds.') {
    throw "Unexpected overall timeout validation: $invalidOverall"
}

$invalidOverallUpperBound = $null
try {
    New-SideyStartupSmokeTimeoutState `
        -StartedAt $startedAt `
        -InactivityTimeoutSeconds 30 `
        -OverallTimeoutSeconds 601 | Out-Null
}
catch {
    $invalidOverallUpperBound = $_.Exception.Message
}
if ($invalidOverallUpperBound -cne 'Startup smoke overall timeout must be between 30 and 600 seconds.') {
    throw "Unexpected overall timeout upper-bound validation: $invalidOverallUpperBound"
}

Write-Host 'Published application timeout tests passed.'
