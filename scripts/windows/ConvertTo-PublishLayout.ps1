#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDirectory,

    [Parameter(Mandatory = $true)]
    [string]$LauncherSourcePath,

    [Parameter(Mandatory = $true)]
    [string]$UninstallerSourcePath,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$FileVersion
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$publishDirectoryPath = (Resolve-Path -LiteralPath $PublishDirectory).Path
$launcherSourceFilePath = (Resolve-Path -LiteralPath $LauncherSourcePath).Path
$uninstallerSourceFilePath = (Resolve-Path -LiteralPath $UninstallerSourcePath).Path
$runtimeDirectory = Join-Path $publishDirectoryPath 'Runtime'
$assetsDirectory = Join-Path $publishDirectoryPath 'Assets'
$languageDirectory = Join-Path $publishDirectoryPath 'Langs'
$legacyLanguageDirectory = Join-Path $publishDirectoryPath 'Lang'
$launcherPath = Join-Path $publishDirectoryPath 'SIDEY.exe'
$uninstallerPath = Join-Path $publishDirectoryPath 'Uninstall.exe'
$hostPath = Join-Path $runtimeDirectory 'SIDEY.Host.exe'

if (Test-Path -LiteralPath $runtimeDirectory) {
    $runtimeParent = [IO.Directory]::GetParent($runtimeDirectory).FullName
    if (-not [string]::Equals(
        $runtimeParent,
        $publishDirectoryPath,
        [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe Runtime directory: $runtimeDirectory"
    }
    Remove-Item -LiteralPath $runtimeDirectory -Recurse -Force
}
[IO.Directory]::CreateDirectory($runtimeDirectory) | Out-Null
[IO.Directory]::CreateDirectory($languageDirectory) | Out-Null

if (Test-Path -LiteralPath $legacyLanguageDirectory -PathType Container) {
    Get-ChildItem -LiteralPath $legacyLanguageDirectory -Force |
        ForEach-Object {
            Move-Item -LiteralPath $_.FullName -Destination $languageDirectory -Force
        }
    Remove-Item -LiteralPath $legacyLanguageDirectory -Force
}

foreach ($catalogName in @('ko-KR.json', 'en-US.json')) {
    $catalogPath = Join-Path $languageDirectory $catalogName
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
        throw "Published language catalog is missing: $catalogPath"
    }
}

$preservedNames = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($name in @(
    'Assets',
    'Langs',
    'Runtime')) {
    [void]$preservedNames.Add($name)
}

Get-ChildItem -LiteralPath $publishDirectoryPath -Force |
    Where-Object { -not $preservedNames.Contains($_.Name) } |
    ForEach-Object {
        Move-Item -LiteralPath $_.FullName -Destination $runtimeDirectory -Force
    }

$publishedHost = Join-Path $runtimeDirectory 'SIDEY.Host.exe'
if (-not (Test-Path -LiteralPath $publishedHost -PathType Leaf)) {
    throw "Published WinUI host is missing: $publishedHost"
}
$legacyHost = Join-Path $runtimeDirectory 'SIDEY.exe'
$legacyAssembly = Join-Path $runtimeDirectory 'SIDEY.dll'
if (Test-Path -LiteralPath $legacyHost -PathType Leaf) {
    Remove-Item -LiteralPath $legacyHost -Force
}
if (Test-Path -LiteralPath $legacyAssembly -PathType Leaf) {
    Remove-Item -LiteralPath $legacyAssembly -Force
}

if (-not (Test-Path -LiteralPath $assetsDirectory -PathType Container)) {
    throw "Published Assets directory is missing: $assetsDirectory"
}
# Compiled PRI/XAML stays beside the host. File assets, including the title bar
# icon, are loaded explicitly from the deployment root; no private copy is needed.

$assemblyVersion = [Version]$FileVersion
function New-SideyExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$OutputAssembly,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $assemblyInfoName = [IO.Path]::GetFileNameWithoutExtension($OutputAssembly) + '.AssemblyInfo.cs'
    $assemblyInfoPath = Join-Path $runtimeDirectory $assemblyInfoName
    $assemblyInfo = @"
using System.Reflection;
[assembly: AssemblyTitle("$Title")]
[assembly: AssemblyProduct("SIDEY")]
[assembly: AssemblyCompany("SIDEY")]
[assembly: AssemblyDescription("$Description")]
[assembly: AssemblyVersion("$assemblyVersion")]
[assembly: AssemblyFileVersion("$assemblyVersion")]
[assembly: AssemblyInformationalVersion("$Version")]
"@
    [IO.File]::WriteAllText(
        $assemblyInfoPath,
        $assemblyInfo,
        [Text.UTF8Encoding]::new($false))

    $iconPath = Join-Path $assetsDirectory 'Icons\SideyAppIcon.ico'
    $compilerOptions = '/optimize+ /nologo'
    if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
        $compilerOptions += " /win32icon:`"$iconPath`""
    }
    $compilerParameters = [CodeDom.Compiler.CompilerParameters]::new()
    $compilerParameters.CompilerOptions = "$compilerOptions /target:winexe"
    $compilerParameters.GenerateExecutable = $true
    $compilerParameters.OutputAssembly = $OutputAssembly
    [void]$compilerParameters.ReferencedAssemblies.Add('System.dll')
    try {
        Add-Type `
            -Path @($SourcePath, $assemblyInfoPath) `
            -CompilerParameters $compilerParameters
    }
    finally {
        Remove-Item -LiteralPath $assemblyInfoPath -Force
    }
}

New-SideyExecutable `
    -SourcePath $launcherSourceFilePath `
    -OutputAssembly $launcherPath `
    -Title 'SIDEY Launcher' `
    -Description 'SIDEY desktop launcher'
New-SideyExecutable `
    -SourcePath $uninstallerSourceFilePath `
    -OutputAssembly $uninstallerPath `
    -Title 'SIDEY Uninstaller' `
    -Description 'SIDEY uninstaller'

Write-Host "PublishLayout=SIDEY.exe + Uninstall.exe + Assets + Langs + Runtime/SIDEY.Host.exe"
