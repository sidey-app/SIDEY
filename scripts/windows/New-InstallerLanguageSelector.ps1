#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$NsisDirectory
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Sidey.PowerShell.psm1') -Force
$repositoryRootPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$outputFilePath = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFilePath)) | Out-Null
$compilerPath = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
if (-not (Test-Path -LiteralPath $compilerPath -PathType Leaf)) {
    throw 'Build the language selector with Windows PowerShell / the OS .NET Framework compiler.'
}
$installerSourceDirectory = Join-Path $repositoryRootPath 'windows/installer/Sidey.Setup'
$iconPath = Join-Path $repositoryRootPath 'windows/src/Sidey.App/Assets/Icons/SideyAppIcon.ico'
if (-not $NsisDirectory) { $NsisDirectory = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'NSIS' }
$languagePluginPath = (Resolve-Path -LiteralPath (Join-Path $NsisDirectory 'Plugins/x86-unicode/LangDLL.dll')).Path
# Reuse the actual NSIS dialog template, including its icon, font and control
# layout. Only this resource is embedded; no NSIS DLL is needed at runtime.
Add-Type @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class NsisLanguageDialogResource {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr FindResource(IntPtr module, IntPtr name, IntPtr type);
    [DllImport("kernel32.dll")] static extern uint SizeofResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll")] static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll")] static extern IntPtr LockResource(IntPtr resource);
    [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr module);
    public static byte[] Read(string path) {
        IntPtr module = LoadLibraryEx(path, IntPtr.Zero, 2); // LOAD_LIBRARY_AS_DATAFILE
        if (module == IntPtr.Zero) throw new Win32Exception();
        try {
            IntPtr resource = FindResource(module, (IntPtr)101, (IntPtr)5); // RT_DIALOG
            if (resource == IntPtr.Zero) throw new Win32Exception();
            byte[] bytes = new byte[SizeofResource(module, resource)];
            IntPtr data = LockResource(LoadResource(module, resource));
            if (data == IntPtr.Zero || bytes.Length == 0) throw new Win32Exception();
            Marshal.Copy(data, bytes, 0, bytes.Length);
            return bytes;
        } finally { FreeLibrary(module); }
    }
}
'@
$dialogResourcePath = Join-Path ([IO.Path]::GetDirectoryName($outputFilePath)) 'LanguageDialog.bin'
[IO.File]::WriteAllBytes($dialogResourcePath, [NsisLanguageDialogResource]::Read($languagePluginPath))
Invoke-SideyNativeCommand `
    -FilePath $compilerPath `
    -ArgumentList @(
        '/nologo',
        '/target:winexe',
        '/optimize+',
        '/utf8output',
        '/codepage:65001',
        '/reference:System.dll',
        '/reference:System.Core.dll',
        '/reference:System.Drawing.dll',
        "/resource:$dialogResourcePath,Sidey.Installer.LanguageDialog",
        "/win32manifest:$(Join-Path $installerSourceDirectory 'LanguageSelector.manifest')",
        "/win32icon:$iconPath",
        "/out:$outputFilePath",
        (Join-Path $installerSourceDirectory 'InstallerLanguages.cs'),
        (Join-Path $installerSourceDirectory 'LanguageSelector.cs')
    ) `
    -Description 'Installer language selector compilation'
