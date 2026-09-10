#requires -Version 5.1

[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$PublishDirectory)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repositoryRootPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$publishDirectoryPath = (Resolve-Path -LiteralPath $PublishDirectory).Path
if (Test-Path -LiteralPath (Join-Path $publishDirectoryPath 'Runtime/Assets')) {
    throw 'Duplicate Runtime/Assets must not be included; use the deployment root Assets.'
}
$prerequisiteConfiguration = Get-Content -LiteralPath (Join-Path $repositoryRootPath 'windows/installer/Sidey.Setup/prerequisites.json') -Raw | ConvertFrom-Json
$runtimeConfiguration = Get-Content -LiteralPath (Join-Path $publishDirectoryPath 'Runtime/SIDEY.Host.runtimeconfig.json') -Raw | ConvertFrom-Json
$runtimeOptions = $runtimeConfiguration.runtimeOptions
$frameworkProperty = $runtimeOptions.PSObject.Properties['framework']
$frameworksProperty = $runtimeOptions.PSObject.Properties['frameworks']
$includedFrameworksProperty = $runtimeOptions.PSObject.Properties['includedFrameworks']
$frameworks = @()
if ($null -ne $frameworkProperty) {
    $frameworks += @($frameworkProperty.Value)
}
if ($null -ne $frameworksProperty) {
    $frameworks += @($frameworksProperty.Value)
}
$frameworks = @($frameworks | Where-Object { $null -ne $_ })
if (($null -ne $includedFrameworksProperty -and $includedFrameworksProperty.Value) -or
    $frameworks.Count -ne 1 -or
    $frameworks[0].name -cne 'Microsoft.NETCore.App' -or
    [version]$frameworks[0].version -ne [version]$prerequisiteConfiguration.dotnet.minimumVersion) {
    throw 'Publish must require the configured shared .NET Runtime, without includedFrameworks.'
}
$dependencyManifest = Get-Content -LiteralPath (Join-Path $publishDirectoryPath 'Runtime/SIDEY.Host.deps.json') -Raw | ConvertFrom-Json
if (@($dependencyManifest.libraries.PSObject.Properties.Name | Where-Object { $_ -match '^runtimepack\.Microsoft\.(NETCore|WindowsDesktop|AspNetCore)\.App' }).Count) {
    throw 'A self-contained runtime pack remains in the published dependency manifest.'
}

# Check the resolved NuGet SDK, not a separately guessed WinUI version.
$projectAssets = Get-Content -LiteralPath (Join-Path $repositoryRootPath 'windows/src/Sidey.App/obj/project.assets.json') -Raw | ConvertFrom-Json
$runtimePackage = @($projectAssets.libraries.PSObject.Properties | Where-Object { $_.Name -like 'Microsoft.WindowsAppSDK.Runtime/*' })
if ($runtimePackage.Count -ne 1 -or
    $runtimePackage[0].Name -cne "Microsoft.WindowsAppSDK.Runtime/$($prerequisiteConfiguration.windowsAppRuntime.sdkVersion)") {
    throw 'Update prerequisites.json for the resolved Windows App SDK Runtime version.'
}
$packagePath = $null
foreach ($folder in $projectAssets.packageFolders.PSObject.Properties.Name) {
    $packageCandidatePath = Join-Path $folder $runtimePackage[0].Value.path
    if (Test-Path -LiteralPath $packageCandidatePath -PathType Container) {
        $packagePath = $packageCandidatePath
        break
    }
}
if (-not $packagePath) { throw 'Restored Windows App SDK Runtime package was not found.' }
$versionInfo = Get-Content -LiteralPath (Join-Path $packagePath 'WindowsAppSDK-VersionInfo.json') -Raw | ConvertFrom-Json
$families = @($versionInfo.Runtime.Packages.Framework.PackageFamilyName,
    $versionInfo.Runtime.Packages.Main.PackageFamilyName,
    $versionInfo.Runtime.Packages.Singleton.PackageFamilyName,
    $versionInfo.Runtime.Packages.DDLM.X64.PackageFamilyName)
if (@(Compare-Object $families @($prerequisiteConfiguration.windowsAppRuntime.packages.family)).Count) {
    throw 'Prerequisite package identities do not match the resolved SDK.'
}
foreach ($package in $prerequisiteConfiguration.windowsAppRuntime.packages) {
    $expectedVersion = $versionInfo.Runtime.Version.String
    if ($package.family -eq $versionInfo.Runtime.Packages.Singleton.PackageFamilyName) {
        $expectedVersion = $versionInfo.Runtime.VersionSingleton.String
    }
    if ($package.minimumVersion -cne $expectedVersion) { throw 'Prerequisite package version differs from the SDK.' }
}

$forbidden = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($name in @('coreclr.dll', 'clrjit.dll', 'hostfxr.dll', 'hostpolicy.dll',
    'System.Private.CoreLib.dll', 'mscordaccore.dll', 'mscordbi.dll', 'createdump.exe',
    'dotnet.exe', 'WindowsAppRuntimeInstall.exe', 'windowsappruntimeinstall-x64.exe')) {
    [void]$forbidden.Add($name)
}
# Inspect every native DLL supplied by the shared framework, including ML DLLs
# that NuGet can copy independently even when WindowsAppSDKSelfContained=false.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $packagePath 'tools/MSIX/win10-x64/Microsoft.WindowsAppRuntime.2.msix'))
try {
    foreach ($entry in $archive.Entries) {
        if ($entry.Name.EndsWith('.dll', [StringComparison]::OrdinalIgnoreCase)) {
            [void]$forbidden.Add($entry.Name)
        }
    }
}
finally { $archive.Dispose() }
$publishedFiles = @(Get-ChildItem -LiteralPath $publishDirectoryPath -Recurse -File)
$unexpectedFiles = @($publishedFiles | Where-Object {
    $forbidden.Contains($_.Name) -or $_.Extension -in @('.msix', '.msixbundle', '.appx', '.appxbundle') -or
    $_.Name -match '^(dotnet|windowsdesktop|aspnetcore)-runtime.*\.exe$'
})
if ($unexpectedFiles.Count) { throw "Shared runtime payload found: $($unexpectedFiles.Name -join ', ')" }
foreach ($required in @('Microsoft.WindowsAppRuntime.Bootstrap.dll', 'Microsoft.WindowsAppRuntime.Bootstrap.Net.dll', 'Microsoft.WinUI.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $publishDirectoryPath "Runtime/$required") -PathType Leaf)) {
        throw "Required bootstrapper or managed projection missing: $required"
    }
}
& (Join-Path $PSScriptRoot 'Test-ImpactAudioAssets.ps1') -AssetsDirectory (Join-Path $publishDirectoryPath 'Assets')
Write-Host "FrameworkDependentPublish=true; Files=$($publishedFiles.Count); Bytes=$(($publishedFiles | Measure-Object Length -Sum).Sum); SharedRuntimeFiles=0"
