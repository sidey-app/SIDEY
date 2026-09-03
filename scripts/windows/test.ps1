[CmdletBinding()]
param(
    [string]$Version = '1.0.5'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$solution = Join-Path $repositoryRoot 'windows/SIDEY.Windows.slnx'
$testProject = Join-Path $repositoryRoot 'windows/tests/Sidey.Core.Tests/Sidey.Core.Tests.csproj'
$platformTestProject = Join-Path $repositoryRoot 'windows/tests/Sidey.Platform.Windows.Tests/Sidey.Platform.Windows.Tests.csproj'

Push-Location (Join-Path $repositoryRoot 'windows')
try {
    dotnet restore $solution
    dotnet test $testProject --configuration Release --no-restore
    dotnet test $platformTestProject --configuration Release --no-restore
    dotnet build $solution --configuration Release --no-restore
    dotnet publish (Join-Path $repositoryRoot 'windows/src/Sidey.App/Sidey.App.csproj') `
        --configuration Release `
        --runtime win-x64 `
        --self-contained true `
        --no-restore `
        "-p:Version=$Version" `
        -p:PublishSingleFile=false `
        --output (Join-Path $repositoryRoot 'build/windows/publish-smoke')
    & (Join-Path $repositoryRoot 'scripts/windows/smoke-launch.ps1') `
        -PublishDir (Join-Path $repositoryRoot 'build/windows/publish-smoke')
    if ($LASTEXITCODE -ne 0) {
        throw "SIDEY 게시 실행 스모크 테스트 실패"
    }
}
finally {
    Pop-Location
}
