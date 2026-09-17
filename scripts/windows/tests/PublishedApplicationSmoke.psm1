#requires -Version 5.1

Set-StrictMode -Version 3.0

function New-SideyStartupSmokeTimeoutState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [DateTimeOffset]$StartedAt,

        [Parameter(Mandatory = $true)]
        [int]$InactivityTimeoutSeconds,

        [Parameter(Mandatory = $true)]
        [int]$OverallTimeoutSeconds
    )

    if ($InactivityTimeoutSeconds -lt 5 -or $InactivityTimeoutSeconds -gt 120) {
        throw 'Startup smoke inactivity timeout must be between 5 and 120 seconds.'
    }
    if ($OverallTimeoutSeconds -lt $InactivityTimeoutSeconds -or
        $OverallTimeoutSeconds -gt 600) {
        throw "Startup smoke overall timeout must be between $InactivityTimeoutSeconds and 600 seconds."
    }

    return [pscustomobject]@{
        InactivityTimeoutSeconds = $InactivityTimeoutSeconds
        InactivityDeadline = $StartedAt.AddSeconds($InactivityTimeoutSeconds)
        OverallDeadline = $StartedAt.AddSeconds($OverallTimeoutSeconds)
    }
}

function Update-SideyStartupSmokeTimeoutState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State,

        [Parameter(Mandatory = $true)]
        [DateTimeOffset]$ObservedAt
    )

    $inactivityDeadline = $ObservedAt.AddSeconds($State.InactivityTimeoutSeconds)
    if ($inactivityDeadline -gt $State.OverallDeadline) {
        $inactivityDeadline = $State.OverallDeadline
    }
    return [pscustomobject]@{
        InactivityTimeoutSeconds = $State.InactivityTimeoutSeconds
        InactivityDeadline = $inactivityDeadline
        OverallDeadline = $State.OverallDeadline
    }
}

function Get-SideyStartupSmokeTimeoutReason {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State,

        [Parameter(Mandatory = $true)]
        [DateTimeOffset]$ObservedAt
    )

    if ($ObservedAt -ge $State.OverallDeadline) {
        return 'Overall'
    }
    if ($ObservedAt -ge $State.InactivityDeadline) {
        return 'NoProgress'
    }
    return $null
}

function Resolve-SideyStartupSmokeObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State,

        [Parameter(Mandatory = $true)]
        [DateTimeOffset]$ObservedAt,

        [switch]$HasProgress,

        [switch]$HasCompleted
    )

    $timeoutReason = Get-SideyStartupSmokeTimeoutReason `
        -State $State `
        -ObservedAt $ObservedAt
    if ($null -ne $timeoutReason) {
        return [pscustomobject]@{
            State = $State
            TimeoutReason = $timeoutReason
            Ready = $false
        }
    }
    if ($HasProgress) {
        $State = Update-SideyStartupSmokeTimeoutState `
            -State $State `
            -ObservedAt $ObservedAt
    }
    return [pscustomobject]@{
        State = $State
        TimeoutReason = $null
        Ready = [bool]$HasCompleted
    }
}

Export-ModuleMember -Function `
    Get-SideyStartupSmokeTimeoutReason, `
    New-SideyStartupSmokeTimeoutState, `
    Resolve-SideyStartupSmokeObservation, `
    Update-SideyStartupSmokeTimeoutState
