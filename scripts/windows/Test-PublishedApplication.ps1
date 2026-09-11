#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDirectory,

    [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$publishDirectoryPath = (Resolve-Path -LiteralPath $PublishDirectory).Path
$launcherExecutablePath = Join-Path $publishDirectoryPath 'SIDEY.exe'
$hostExecutablePath = Join-Path $publishDirectoryPath 'Runtime\SIDEY.Host.exe'
if (Test-Path -LiteralPath (Join-Path $publishDirectoryPath 'Runtime/Assets')) {
    throw 'Startup smoke must use external Assets without a private Runtime/Assets copy.'
}
if (-not (Test-Path -LiteralPath $launcherExecutablePath -PathType Leaf)) {
    throw "SIDEY.exe was not found in the publish directory: $publishDirectoryPath"
}
if (-not (Test-Path -LiteralPath $hostExecutablePath -PathType Leaf)) {
    throw "Runtime/SIDEY.Host.exe was not found in the publish directory: $publishDirectoryPath"
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
        -FilePath $launcherExecutablePath `
        -WorkingDirectory $publishDirectoryPath `
        -WindowStyle Hidden `
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
                        $hostExecutablePath,
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
            if ($log -match "$pidPattern fatal ") {
                throw "SIDEY startup composer probe failed.`n$log"
            }
            if ($log -match "$pidPattern .*stage=composer-smoke-complete" -and
                $log -match "$pidPattern .*stage=external-assets-smoke-complete") {
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
        throw "SIDEY.exe did not complete its startup composer probe within $TimeoutSeconds seconds.`n$tail"
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
