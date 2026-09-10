#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TestVersion,

    [switch]$BuildOnly
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Sidey.PowerShell.psm1') -Force
$repositoryRootPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$releaseManifestPath = Join-Path $repositoryRootPath 'release/windows.json'
$releaseManifest = Get-Content -LiteralPath $releaseManifestPath -Raw | ConvertFrom-Json
$publicVersion = [Version]$releaseManifest.version

if ($TestVersion -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
    throw "테스트 버전은 숫자 세 부분이어야 합니다: $TestVersion"
}
if ([Version]$TestVersion -ge $publicVersion) {
    throw "테스트 버전은 공개 Windows 버전 $publicVersion 보다 낮아야 합니다."
}

$publishDirectory = Join-Path $repositoryRootPath 'build/windows/update-design-test'
$hostExecutablePath = Join-Path $publishDirectory 'Runtime/SIDEY.Host.exe'
$hostAssemblyPath = Join-Path $publishDirectory 'Runtime/SIDEY.Host.dll'
$launcherExecutablePath = Join-Path $publishDirectory 'SIDEY.exe'
$runningHosts = @(Get-Process -Name 'SIDEY.Host' -ErrorAction SilentlyContinue)
if (-not $BuildOnly -and $runningHosts.Count -gt 0) {
    $runningPaths = $runningHosts |
        ForEach-Object { $_.Path } |
        Where-Object { $_ } |
        Sort-Object -Unique
    throw "실행 중인 SIDEY를 먼저 종료해 주세요: $($runningPaths -join ', ')"
}

Invoke-SideyNativeCommand `
    -FilePath 'dotnet' `
    -ArgumentList @(
        'publish',
        (Join-Path $repositoryRootPath 'windows/src/Sidey.App/Sidey.App.csproj'),
        '--configuration', 'Release',
        '--runtime', 'win-x64',
        '--self-contained', 'false',
        '-p:WindowsAppSDKSelfContained=false',
        '-p:PublishSingleFile=false',
        "-p:Version=$TestVersion",
        "-p:FileVersion=$TestVersion.0",
        "-p:AssemblyVersion=$TestVersion.0",
        '--output', $publishDirectory
    ) `
    -Description 'Update design test publish'

$publishedVersion = [Reflection.AssemblyName]::GetAssemblyName($hostAssemblyPath).Version.ToString(3)
if ($publishedVersion -ne $TestVersion) {
    throw "테스트 빌드 버전이 일치하지 않습니다: $publishedVersion / $TestVersion"
}

Write-Host "UpdateDesignTestVersion=$TestVersion"
Write-Host "PublishedUpdateVersion=$publicVersion"
Write-Host "PublishDirectory=$publishDirectory"
if ($BuildOnly) {
    return
}

Invoke-SideyNativeCommand `
    -FilePath 'powershell.exe' `
    -ArgumentList @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $repositoryRootPath 'windows/installer/Sidey.Setup/SetupRuntime.ps1')
    ) `
    -Description 'Runtime prerequisite setup'

$firstLaunch = Start-Process `
    -FilePath $launcherExecutablePath `
    -WorkingDirectory $publishDirectory `
    -PassThru
$firstLaunch.WaitForExit()
if ($firstLaunch.ExitCode -ne 0) {
    throw "업데이트 디자인 테스트 앱을 시작하지 못했습니다."
}

$deadline = [DateTimeOffset]::UtcNow.AddSeconds(30)
$hostProcess = $null
while ($null -eq $hostProcess -and [DateTimeOffset]::UtcNow -lt $deadline) {
    $hostProcess = Get-Process -Name 'SIDEY.Host' -ErrorAction SilentlyContinue |
        Where-Object {
            [string]::Equals(
                $_.Path,
                $hostExecutablePath,
                [StringComparison]::OrdinalIgnoreCase)
        } |
        Select-Object -First 1
    if ($null -eq $hostProcess) {
        Start-Sleep -Milliseconds 250
    }
}
if ($null -eq $hostProcess) {
    throw "업데이트 디자인 테스트 앱이 30초 안에 시작되지 않았습니다."
}

$startupDeadline = [DateTimeOffset]::UtcNow.AddSeconds(30)
$logDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'SIDEY/Logs'
$startupComplete = $false
while (-not $startupComplete -and [DateTimeOffset]::UtcNow -lt $startupDeadline) {
    $hostProcess.Refresh()
    if ($hostProcess.HasExited) {
        throw "업데이트 디자인 테스트 앱이 시작 중 종료되었습니다."
    }

    $startupLogMatch = Get-ChildItem `
        -LiteralPath $logDirectory `
        -File `
        -Filter "SIDEY.$($TestVersion.Replace('.', '_')).*.log" `
        -ErrorAction SilentlyContinue |
        Select-String -Pattern "pid=$($hostProcess.Id) .*startup-complete" |
        Select-Object -First 1
    $startupComplete = $null -ne $startupLogMatch
    if (-not $startupComplete) {
        Start-Sleep -Milliseconds 250
    }
}
if (-not $startupComplete) {
    throw "업데이트 디자인 테스트 앱이 30초 안에 초기화를 완료하지 못했습니다."
}

$showSettings = Start-Process `
    -FilePath $launcherExecutablePath `
    -WorkingDirectory $publishDirectory `
    -PassThru
$showSettings.WaitForExit()
if ($showSettings.ExitCode -ne 0) {
    throw "업데이트 디자인 테스트 설정창을 열지 못했습니다."
}

Write-Host "ProcessId=$($hostProcess.Id)"
Write-Host "설정 > 업데이트에서 v$publicVersion 업데이트 안내와 확인 대화상자를 테스트하세요."
