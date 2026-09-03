[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDir,

    [Parameter(Mandatory = $true)]
    [string]$LauncherSource,

    [Parameter(Mandatory = $true)]
    [string]$UninstallerSource,

    [string]$Version = '1.0.5',

    [string]$FileVersion = '1.0.5.0'
)

$ErrorActionPreference = 'Stop'
$resolvedPublishDir = (Resolve-Path -LiteralPath $PublishDir).Path
$resolvedLauncherSource = (Resolve-Path -LiteralPath $LauncherSource).Path
$resolvedUninstallerSource = (Resolve-Path -LiteralPath $UninstallerSource).Path
$runtimeDirectory = Join-Path $resolvedPublishDir 'Runtime'
$assetsDirectory = Join-Path $resolvedPublishDir 'Assets'
$languageDirectory = Join-Path $resolvedPublishDir 'Langs'
$legacyLanguageDirectory = Join-Path $resolvedPublishDir 'Lang'
$launcherPath = Join-Path $resolvedPublishDir 'SIDEY.exe'
$uninstallerPath = Join-Path $resolvedPublishDir 'Uninstall.exe'
$hostPath = Join-Path $runtimeDirectory 'SIDEY.Host.exe'
$previewPath = Join-Path $resolvedPublishDir 'SIDEY-Onboarding-Preview.cmd'

if (Test-Path -LiteralPath $runtimeDirectory) {
    $runtimeParent = [IO.Directory]::GetParent($runtimeDirectory).FullName
    if (-not [string]::Equals(
        $runtimeParent,
        $resolvedPublishDir,
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
    'Runtime',
    'SIDEY-Onboarding-Preview.cmd')) {
    [void]$preservedNames.Add($name)
}

Get-ChildItem -LiteralPath $resolvedPublishDir -Force |
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
# WinUI's PRI/XAML loader resolves compiled app resources beside the real host.
# SIDEY resolves mutable assets from the deployment root, while this private
# copy keeps native XAML resource loading intact inside the opaque Runtime tree.
Copy-Item `
    -LiteralPath $assetsDirectory `
    -Destination (Join-Path $runtimeDirectory 'Assets') `
    -Recurse `
    -Force

$assemblyVersion = [Version]$FileVersion
function Build-SideyExecutable {
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

Build-SideyExecutable `
    -SourcePath $resolvedLauncherSource `
    -OutputAssembly $launcherPath `
    -Title 'SIDEY Launcher' `
    -Description 'SIDEY desktop launcher'
Build-SideyExecutable `
    -SourcePath $resolvedUninstallerSource `
    -OutputAssembly $uninstallerPath `
    -Title 'SIDEY Uninstaller' `
    -Description 'SIDEY uninstaller'

$preview = "@echo off`r`nsetlocal`r`nstart `"`" `"%~dp0SIDEY.exe`" --onboarding-preview`r`n"
[IO.File]::WriteAllText($previewPath, $preview, [Text.ASCIIEncoding]::new())

Write-Host "PublishLayout=SIDEY.exe + Uninstall.exe + Assets + Langs + Runtime/SIDEY.Host.exe"
