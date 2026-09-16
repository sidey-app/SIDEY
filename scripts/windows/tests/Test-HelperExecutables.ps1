#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PublishDirectory,
    [Parameter(Mandatory = $true)][string]$SelectorExecutablePath,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$FileVersion,
    [Parameter(Mandatory = $true)][string]$NsisDirectory
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$builder = Join-Path $PSScriptRoot '../New-SideyHelperExecutable.ps1'
$icon = Join-Path $root 'windows/src/Sidey.App/Assets/Icons/SideyAppIcon.ico'
# A fresh directory forces independent compilation and exercises paths with spaces.
$probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('SIDEY helper verification ' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($probeRoot)
$languages = Join-Path $root 'windows/installer/Sidey.Setup/InstallerLanguages.cs'
$helpers = @(
    @{ Name = 'SIDEY.exe'; Title = 'SIDEY Launcher'; Description = 'SIDEY desktop launcher';
       Sources = @((Join-Path $root 'windows/src/Sidey.Launcher/Program.cs'), $languages);
       Original = (Join-Path $PublishDirectory 'SIDEY.exe') },
    @{ Name = 'Uninstall.exe'; Title = 'SIDEY Uninstaller'; Description = 'SIDEY uninstaller';
       Sources = @((Join-Path $root 'windows/src/Sidey.Uninstaller/Program.cs'));
       Original = (Join-Path $PublishDirectory 'Uninstall.exe') },
    @{ Name = 'Sidey.SetupLanguage.exe'; Title = 'SIDEY Installer Language';
       Original = $SelectorExecutablePath }
)

foreach ($helper in $helpers) {
    $rebuilt = Join-Path $probeRoot $helper.Name
    if ($helper.Name -eq 'Sidey.SetupLanguage.exe') {
        # Use a fresh PowerShell process because the dialog resource reader is a
        # build-time Add-Type helper with a process-wide type name.
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
            -File (Join-Path $PSScriptRoot '../New-InstallerLanguageSelector.ps1') `
            -OutputPath $rebuilt -Version $Version -FileVersion $FileVersion -NsisDirectory $NsisDirectory
        if ($LASTEXITCODE -ne 0) { throw 'Independent language selector build failed.' }
    }
    else {
        & $builder -SourcePath $helper.Sources -OutputPath $rebuilt `
            -Title $helper.Title -Description $helper.Description `
            -Version $Version -FileVersion $FileVersion -IconPath $icon
    }

    $original = (Resolve-Path -LiteralPath $helper.Original).Path
    $originalHash = (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
    $rebuiltHash = (Get-FileHash -LiteralPath $rebuilt -Algorithm SHA256).Hash
    if ($originalHash -cne $rebuiltHash) {
        throw "Helper is not reproducible from the current sources: $($helper.Name)"
    }
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($original)
    if ($info.ProductName -cne 'SIDEY' -or $info.CompanyName -cne 'SIDEY' -or
        $info.FileVersion -cne $FileVersion -or $info.ProductVersion -cne $Version -or
        $info.FileDescription -cne $helper.Title) {
        throw "Helper product/version metadata does not match: $($helper.Name)"
    }
    if ([Reflection.AssemblyName]::GetAssemblyName($original).Version.ToString() -cne $FileVersion) {
        throw "Helper assembly version does not match: $($helper.Name)"
    }
    Write-Host "Verified helper $($helper.Name) SHA256=$originalHash"
}

# These modes do not show windows, install anything, remove data, or change settings.
foreach ($language in @(1033, 1042, 1041, 2052, 1028, 1049, 1058)) {
    $process = Start-Process -FilePath (Join-Path $probeRoot 'Sidey.SetupLanguage.exe') `
        -ArgumentList @([string]$language, '0', '--silent') -WindowStyle Hidden -PassThru -Wait
    if ($process.ExitCode -ne $language) { throw "Language selection exit code changed: $language" }
}
$process = Start-Process -FilePath (Join-Path $probeRoot 'Uninstall.exe') `
    -ArgumentList '--sidey-invalid-verification-argument' -WindowStyle Hidden -PassThru -Wait
if ($process.ExitCode -ne 64) { throw 'Uninstaller no longer rejects unsupported arguments.' }
$unsafeRuntimeInstaller = Join-Path $probeRoot 'windowsappruntimeinstall-x64.exe'
[IO.File]::WriteAllText($unsafeRuntimeInstaller, 'not an installer')
$process = Start-Process -FilePath (Join-Path $probeRoot 'Uninstall.exe') `
    -ArgumentList ('--run-windows-app-runtime-as-desktop-user "' + $unsafeRuntimeInstaller + '"') `
    -WindowStyle Hidden -PassThru -Wait
if ($process.ExitCode -ne 64) { throw 'Desktop-user runtime runner accepted an unsafe target.' }

$uninstallerAssembly = [Reflection.Assembly]::Load(
    [IO.File]::ReadAllBytes((Join-Path $probeRoot 'Uninstall.exe')))
$uninstallerProgram = $uninstallerAssembly.GetType('Sidey.Uninstaller.Program', $true)
$errorMapper = $uninstallerProgram.GetMethod(
    'GetDesktopUserRunnerErrorCode',
    [Reflection.BindingFlags]'NonPublic,Static')
$mappedError = [int]$errorMapper.Invoke(
    $null,
    [object[]]@([ComponentModel.Win32Exception]::new(193)))
if ($mappedError -ne 193) {
    throw "Desktop-user runner did not preserve ERROR_BAD_EXE_FORMAT (193): $mappedError"
}
Write-Host "Helper verification passed. Evidence directory: $probeRoot"
