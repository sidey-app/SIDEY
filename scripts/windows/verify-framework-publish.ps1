[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$PublishDir)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$publishRoot = (Resolve-Path -LiteralPath $PublishDir).Path
if (Test-Path -LiteralPath (Join-Path $publishRoot 'Runtime/Assets')) {
    throw 'Duplicate Runtime/Assets must not be included; use the deployment root Assets.'
}
$configuration = Get-Content -LiteralPath (Join-Path $repositoryRoot 'windows/installer/Sidey.Setup/prerequisites.json') -Raw | ConvertFrom-Json
$runtimeConfig = Get-Content -LiteralPath (Join-Path $publishRoot 'Runtime/SIDEY.Host.runtimeconfig.json') -Raw | ConvertFrom-Json
$frameworks = @($runtimeConfig.runtimeOptions.framework) + @($runtimeConfig.runtimeOptions.frameworks)
$frameworks = @($frameworks | Where-Object { $null -ne $_ })
if ($runtimeConfig.runtimeOptions.includedFrameworks -or $frameworks.Count -ne 1 -or
    $frameworks[0].name -cne 'Microsoft.NETCore.App' -or
    [version]$frameworks[0].version -ne [version]$configuration.dotnet.minimumVersion) {
    throw 'Publish must require the configured shared .NET Runtime, without includedFrameworks.'
}
$deps = Get-Content -LiteralPath (Join-Path $publishRoot 'Runtime/SIDEY.Host.deps.json') -Raw | ConvertFrom-Json
if (@($deps.libraries.PSObject.Properties.Name | Where-Object { $_ -match '^runtimepack\.Microsoft\.(NETCore|WindowsDesktop|AspNetCore)\.App' }).Count) {
    throw 'A self-contained runtime pack remains in the published dependency manifest.'
}

# Check the resolved NuGet SDK, not a separately guessed WinUI version.
$assets = Get-Content -LiteralPath (Join-Path $repositoryRoot 'windows/src/Sidey.App/obj/project.assets.json') -Raw | ConvertFrom-Json
$runtimePackage = @($assets.libraries.PSObject.Properties | Where-Object { $_.Name -like 'Microsoft.WindowsAppSDK.Runtime/*' })
if ($runtimePackage.Count -ne 1 -or
    $runtimePackage[0].Name -cne "Microsoft.WindowsAppSDK.Runtime/$($configuration.windowsAppRuntime.sdkVersion)") {
    throw 'Update prerequisites.json for the resolved Windows App SDK Runtime version.'
}
$packagePath = $null
foreach ($folder in $assets.packageFolders.PSObject.Properties.Name) {
    $candidate = Join-Path $folder $runtimePackage[0].Value.path
    if (Test-Path -LiteralPath $candidate -PathType Container) { $packagePath = $candidate; break }
}
if (-not $packagePath) { throw 'Restored Windows App SDK Runtime package was not found.' }
$versionInfo = Get-Content -LiteralPath (Join-Path $packagePath 'WindowsAppSDK-VersionInfo.json') -Raw | ConvertFrom-Json
$families = @($versionInfo.Runtime.Packages.Framework.PackageFamilyName,
    $versionInfo.Runtime.Packages.Main.PackageFamilyName,
    $versionInfo.Runtime.Packages.Singleton.PackageFamilyName,
    $versionInfo.Runtime.Packages.DDLM.X64.PackageFamilyName)
if (@(Compare-Object $families @($configuration.windowsAppRuntime.packages.family)).Count) {
    throw 'Prerequisite package identities do not match the resolved SDK.'
}
foreach ($package in $configuration.windowsAppRuntime.packages) {
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
$files = @(Get-ChildItem -LiteralPath $publishRoot -Recurse -File)
$unexpected = @($files | Where-Object {
    $forbidden.Contains($_.Name) -or $_.Extension -in @('.msix', '.msixbundle', '.appx', '.appxbundle') -or
    $_.Name -match '^(dotnet|windowsdesktop|aspnetcore)-runtime.*\.exe$'
})
if ($unexpected.Count) { throw "Shared runtime payload found: $($unexpected.Name -join ', ')" }
foreach ($required in @('Microsoft.WindowsAppRuntime.Bootstrap.dll', 'Microsoft.WindowsAppRuntime.Bootstrap.Net.dll', 'Microsoft.WinUI.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $publishRoot "Runtime/$required") -PathType Leaf)) {
        throw "Required bootstrapper or managed projection missing: $required"
    }
}
Write-Host "FrameworkDependentPublish=true; Files=$($files.Count); Bytes=$(($files | Measure-Object Length -Sum).Sum); SharedRuntimeFiles=0"
