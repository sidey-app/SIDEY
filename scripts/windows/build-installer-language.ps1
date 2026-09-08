[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$NsisDirectory
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
$compiler = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw 'Build the language selector with Windows PowerShell / the OS .NET Framework compiler.'
}
$sourceRoot = Join-Path $repositoryRoot 'windows/installer/Sidey.Setup'
$icon = Join-Path $repositoryRoot 'windows/src/Sidey.App/Assets/Icons/SideyAppIcon.ico'
if (-not $NsisDirectory) { $NsisDirectory = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'NSIS' }
$langDll = (Resolve-Path -LiteralPath (Join-Path $NsisDirectory 'Plugins/x86-unicode/LangDLL.dll')).Path
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
$template = Join-Path ([IO.Path]::GetDirectoryName($output)) 'LanguageDialog.bin'
[IO.File]::WriteAllBytes($template, [NsisLanguageDialogResource]::Read($langDll))
& $compiler /nologo /target:winexe /optimize+ /utf8output /codepage:65001 `
    /reference:System.dll /reference:System.Core.dll /reference:System.Drawing.dll `
    "/resource:$template,Sidey.Installer.LanguageDialog" `
    "/win32manifest:$(Join-Path $sourceRoot 'LanguageSelector.manifest')" `
    "/win32icon:$icon" "/out:$output" `
    (Join-Path $sourceRoot 'InstallerLanguages.cs') (Join-Path $sourceRoot 'LanguageSelector.cs')
if ($LASTEXITCODE -ne 0) { throw 'Installer language selector compilation failed.' }
