[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDir,

    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
$resolvedPublishDir = (Resolve-Path $PublishDir).Path
$executable = Join-Path $resolvedPublishDir 'SIDEY.exe'
if (-not (Test-Path $executable -PathType Leaf)) {
    throw "실행 스모크 테스트 대상 SIDEY.exe가 없음: $resolvedPublishDir"
}
if ($TimeoutSeconds -lt 5 -or $TimeoutSeconds -gt 120) {
    throw "실행 스모크 테스트 제한 시간은 5~120초여야 함"
}

$logPath = Join-Path $env:LOCALAPPDATA 'SIDEY/Logs/startup.log'
$process = Start-Process `
    -FilePath $executable `
    -WorkingDirectory $resolvedPublishDir `
    -PassThru
$deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
$ready = $false
try {
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        $process.Refresh()
        if ($process.HasExited) {
            $tail = if (Test-Path $logPath -PathType Leaf) {
                (Get-Content -Path $logPath -Tail 40) -join [Environment]::NewLine
            }
            else {
                '(startup.log 없음)'
            }
            throw "SIDEY.exe가 시작 직후 종료됨(exit=$($process.ExitCode)).`n$tail"
        }

        if (Test-Path $logPath -PathType Leaf) {
            $log = Get-Content -Path $logPath -Raw
            $pidPattern = [regex]::Escape("pid=$($process.Id)")
            if ($log -match "$pidPattern .*stage=(main-window-activated|unsupported-window-activated)") {
                $ready = $true
                break
            }
        }
        Start-Sleep -Milliseconds 250
    }

    if (-not $ready) {
        throw "SIDEY.exe가 $TimeoutSeconds초 안에 시작 완료 지점에 도달하지 못함: $logPath"
    }
    Write-Host "StartupSmokeTest=true"
    Write-Host "ProcessId=$($process.Id)"
}
finally {
    $process.Refresh()
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
    }
    $process.Dispose()
}
