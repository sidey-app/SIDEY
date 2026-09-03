[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDir,

    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
$resolvedPublishDir = (Resolve-Path $PublishDir).Path
$executable = Join-Path $resolvedPublishDir 'SIDEY.exe'
$hostExecutable = Join-Path $resolvedPublishDir 'Runtime\SIDEY.Host.exe'
if (-not (Test-Path $executable -PathType Leaf)) {
    throw "SIDEY.exe was not found in the publish directory: $resolvedPublishDir"
}
if (-not (Test-Path $hostExecutable -PathType Leaf)) {
    throw "Runtime/SIDEY.Host.exe was not found in the publish directory: $resolvedPublishDir"
}
if ($TimeoutSeconds -lt 5 -or $TimeoutSeconds -gt 120) {
    throw "Startup smoke timeout must be between 5 and 120 seconds."
}

$smokeDataRoot = Join-Path ([IO.Path]::GetTempPath()) "SIDEY-Smoke-$([Guid]::NewGuid().ToString('N'))"
$logDirectory = Join-Path $smokeDataRoot 'SIDEY/Logs'
$startedAt = [DateTime]::UtcNow.AddSeconds(-1)
$smokeEnvironmentVariable = 'SIDEY_STARTUP_SMOKE'
$smokeDataEnvironmentVariable = 'SIDEY_STARTUP_SMOKE_DATA_ROOT'
$previousSmokeValue = [Environment]::GetEnvironmentVariable($smokeEnvironmentVariable, 'Process')
$previousSmokeDataValue = [Environment]::GetEnvironmentVariable($smokeDataEnvironmentVariable, 'Process')
$process = $null
$launcherProcess = $null
try {
    [Environment]::SetEnvironmentVariable($smokeEnvironmentVariable, '1', 'Process')
    [Environment]::SetEnvironmentVariable($smokeDataEnvironmentVariable, $smokeDataRoot, 'Process')
    $launcherProcess = Start-Process `
        -FilePath $executable `
        -WorkingDirectory $resolvedPublishDir `
        -PassThru
    if (-not $launcherProcess.WaitForExit(5000) -or $launcherProcess.ExitCode -ne 0) {
        throw "SIDEY launcher did not forward startup successfully."
    }
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $ready = $false
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        if ($null -eq $process) {
            $process = Get-Process -Name 'SIDEY.Host' -ErrorAction SilentlyContinue |
                Where-Object {
                    [string]::Equals(
                        $_.Path,
                        $hostExecutable,
                        [StringComparison]::OrdinalIgnoreCase)
                } |
                Select-Object -First 1
            if ($null -eq $process) {
                Start-Sleep -Milliseconds 250
                continue
            }
        }
        $process.Refresh()
        if ($process.HasExited) {
            $recentLogs = @(Get-ChildItem -LiteralPath $logDirectory -Filter 'SIDEY.*.log' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTimeUtc -ge $startedAt } |
                Sort-Object LastWriteTimeUtc)
            $tail = if ($recentLogs.Count -gt 0) {
                ($recentLogs | ForEach-Object { Get-Content -LiteralPath $_.FullName -Tail 40 }) -join [Environment]::NewLine
            }
            else {
                '(SIDEY session log not found)'
            }
            throw "SIDEY.exe exited during startup (exit=$($process.ExitCode)).`n$tail"
        }

        $recentLogs = @(Get-ChildItem -LiteralPath $logDirectory -Filter 'SIDEY.*.log' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $startedAt } |
            Sort-Object LastWriteTimeUtc)
        if ($recentLogs.Count -gt 0) {
            $log = ($recentLogs | ForEach-Object {
                Get-Content -LiteralPath $_.FullName -Raw
            }) -join [Environment]::NewLine
            $pidPattern = [regex]::Escape("pid=$($process.Id)")
            if ($log -match "$pidPattern .*stage=(?:(?:main|onboarding)-window-activated|completed-launch-window-hidden)") {
                $ready = $true
                break
            }
        }
        Start-Sleep -Milliseconds 250
    }

    if (-not $ready) {
        $recentLogs = @(Get-ChildItem -LiteralPath $logDirectory -Filter 'SIDEY.*.log' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $startedAt } |
            Sort-Object LastWriteTimeUtc)
        $tail = if ($recentLogs.Count -gt 0) {
            ($recentLogs | ForEach-Object { Get-Content -LiteralPath $_.FullName -Tail 40 }) -join [Environment]::NewLine
        }
        else {
            '(SIDEY session log not found)'
        }
        throw "SIDEY.exe did not activate its main or onboarding window within $TimeoutSeconds seconds.`n$tail"
    }
    Write-Host "StartupSmokeTest=true"
    Write-Host "ProcessId=$($process.Id)"
}
finally {
    [Environment]::SetEnvironmentVariable(
        $smokeEnvironmentVariable,
        $previousSmokeValue,
        'Process')
    [Environment]::SetEnvironmentVariable(
        $smokeDataEnvironmentVariable,
        $previousSmokeDataValue,
        'Process')
    if ($null -ne $process) {
        $process.Refresh()
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
            $process.WaitForExit()
        }
        $process.Dispose()
    }
    if ($null -ne $launcherProcess) {
        $launcherProcess.Dispose()
    }
}
