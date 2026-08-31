[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
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
}
finally {
    Pop-Location
}
