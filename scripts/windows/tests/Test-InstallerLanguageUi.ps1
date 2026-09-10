#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SelectorExecutablePath,
    [string]$SetupScriptPath,
    [string]$OutputDirectory,
    [string]$MakensisPath = 'C:/Program Files (x86)/NSIS/makensis.exe'
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Sidey.PowerShell.psm1') -Force
$repositoryRootPath = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
if (-not $SetupScriptPath) {
    $SetupScriptPath = Join-Path $repositoryRootPath 'windows/installer/Sidey.Setup/Sidey.Setup.nsi'
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repositoryRootPath 'build/windows/installer-language-ui'
}
$resolvedSelectorExecutablePath = (Resolve-Path -LiteralPath $SelectorExecutablePath).Path
[void][Reflection.Assembly]::LoadFile($resolvedSelectorExecutablePath)
$outputDirectoryPath = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($outputDirectoryPath) | Out-Null
$setupSource = Get-Content -LiteralPath $SetupScriptPath -Raw -Encoding UTF8
$selectionFunction = [regex]::Match($setupSource, '(?ms)^Function SelectInstallerLanguage\r?\n.*?^FunctionEnd').Value
if (-not $selectionFunction) { throw 'Installer language selection function not found.' }
$guiDefine = [regex]::Match($setupSource, '(?m)^!define MUI_CUSTOMFUNCTION_GUIINIT (\w+)').Value
$guiName = [regex]::Match($guiDefine, 'GUIINIT (\w+)').Groups[1].Value
$guiFunction = if ($guiName) { [regex]::Match($setupSource, "(?ms)^Function $guiName\r?\n.*?^FunctionEnd").Value } else { '' }
# Run the production startup functions with a welcome page only: no payload,
# prerequisites, registry writes, elevation, or uninstall actions are included.
$fixtureSource = @'
Unicode true
RequestExecutionLevel user
Name "SIDEY language transition test"
OutFile "@OUTPUT@\LanguageTransition.exe"
!include "MUI2.nsh"
!include "LogicLib.nsh"
!define LANGUAGE_SELECTOR_EXE "@SELECTOR@"
!define PRODUCT_REGISTRY_KEY "Software\SIDEY\Installer"
@GUI_DEFINE@
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_LANGUAGE "English"
LangString LanguageSelectionFailed ${LANG_ENGLISH} "Language selector failed"
Function .onInit
  SetRegView 64
  @SELECTION_CALL@
FunctionEnd
@SELECTION_FUNCTION@
@GUI_FUNCTION@
Section
  Abort
SectionEnd
'@
$fixtureSource = $fixtureSource.Replace('@OUTPUT@', $outputDirectoryPath).Replace('@SELECTOR@', $resolvedSelectorExecutablePath).
    Replace('@GUI_DEFINE@', $guiDefine).Replace('@GUI_FUNCTION@', $guiFunction).
    Replace('@SELECTION_FUNCTION@', $selectionFunction).Replace('@SELECTION_CALL@', 'Call SelectInstallerLanguage')
$fixturePath = Join-Path $outputDirectoryPath 'LanguageTransition.nsi'
[IO.File]::WriteAllText($fixturePath, $fixtureSource, [Text.UTF8Encoding]::new($true))
Invoke-SideyNativeCommand `
    -FilePath $MakensisPath `
    -ArgumentList @('/V2', $fixturePath) `
    -Description 'Language transition fixture compilation'
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class LanguageTransitionProbe {
    public delegate bool EnumProc(IntPtr hwnd, IntPtr state);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc callback, IntPtr state);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc callback, IntPtr state);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("kernel32.dll")] public static extern ushort GetUserDefaultUILanguage();
    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr hwnd, int item);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="SendMessageW")]
    public static extern IntPtr ReadComboText(IntPtr hwnd, uint message, IntPtr wParam, StringBuilder text);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extraInfo);
}
'@
function Find-TestWindow([int]$ProcessId, [string]$Title) {
    $script:foundWindow = [IntPtr]::Zero
    $callback = [LanguageTransitionProbe+EnumProc]{
        param($window, $state)
        $windowProcess = [uint32]0
        [void][LanguageTransitionProbe]::GetWindowThreadProcessId($window, [ref]$windowProcess)
        $text = [Text.StringBuilder]::new(256)
        [void][LanguageTransitionProbe]::GetWindowText($window, $text, 256)
        if ($windowProcess -eq $ProcessId -and $text.ToString() -eq $Title) { $script:foundWindow = $window }
        return $true
    }
    [void][LanguageTransitionProbe]::EnumWindows($callback, [IntPtr]::Zero)
    return $script:foundWindow
}
# This test intentionally displays the two UI windows to verify foreground state.
$process = Start-Process -FilePath (Join-Path $outputDirectoryPath 'LanguageTransition.exe') -PassThru
$helper = $null
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $helper = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($process.Id) AND Name = 'Sidey.SetupLanguage.exe'" | Select-Object -First 1
        $dialog = if ($helper) { Find-TestWindow $helper.ProcessId 'Installer Language' } else { [IntPtr]::Zero }
        if ($dialog -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 100 }
    } while ($dialog -eq [IntPtr]::Zero -and [DateTime]::UtcNow -lt $deadline)
    if ($dialog -eq [IntPtr]::Zero) { throw 'Language selection window did not appear.' }
    $class = [Text.StringBuilder]::new(128)
    [void][LanguageTransitionProbe]::GetClassName($dialog, $class, 128)
    if ($class.ToString() -ne '#32770') { throw 'Language selector must use the original native dialog.' }
    foreach ($item in @{ 1007 = 'Please select a language.'; 1 = 'OK'; 2 = 'Cancel' }.GetEnumerator()) {
        $text = [Text.StringBuilder]::new(256)
        $control = [LanguageTransitionProbe]::GetDlgItem($dialog, $item.Key)
        [void][LanguageTransitionProbe]::GetWindowText($control, $text, 256)
        if ($text.ToString() -cne $item.Value) { throw 'Original NSIS dialog text changed.' }
    }
    $iconControl = [LanguageTransitionProbe]::GetDlgItem($dialog, 1008)
    if ([LanguageTransitionProbe]::SendMessage($iconControl, 0x171, [IntPtr]::Zero, [IntPtr]::Zero) -eq [IntPtr]::Zero) {
        throw 'Original dialog application icon is missing.'
    }
    $combo = [LanguageTransitionProbe]::GetDlgItem($dialog, 1002)
    $expected = [Sidey.Installer.InstallerLanguages]::Ordered([LanguageTransitionProbe]::GetUserDefaultUILanguage())
    $count = [LanguageTransitionProbe]::SendMessage($combo, 0x146, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32()
    if ($count -ne 7) { throw 'Expected seven languages in the native dialog.' }
    for ($index = 0; $index -lt $count; $index++) {
        $text = [Text.StringBuilder]::new(256)
        [void][LanguageTransitionProbe]::ReadComboText($combo, 0x148, [IntPtr]$index, $text)
        if ($text.ToString() -cne $expected[$index].DisplayName) { throw "Unexpected language at index $index." }
    }
    [void][LanguageTransitionProbe]::SetForegroundWindow($dialog)
    if ([LanguageTransitionProbe]::GetForegroundWindow() -ne $dialog) { throw 'Could not establish the selector as foreground for this interactive test.' }
    $script:confirmButton = [IntPtr]::Zero
    $findButton = [LanguageTransitionProbe+EnumProc]{
        param($window, $state)
        $text = [Text.StringBuilder]::new(256)
        [void][LanguageTransitionProbe]::GetWindowText($window, $text, 256)
        if ($text.ToString() -in @('OK', '확인', '确定', '確定', 'ОК')) { $script:confirmButton = $window }
        return $true
    }
    [void][LanguageTransitionProbe]::EnumChildWindows($dialog, $findButton, [IntPtr]::Zero)
    if ($script:confirmButton -eq [IntPtr]::Zero) { throw 'Language confirmation button not found.' }
    # Use input directed at the selector, so Windows foreground permission rules
    # apply as they do for a user accepting it (BM_CLICK would bypass that case).
    [LanguageTransitionProbe]::keybd_event(0x0d, 0, 0, [UIntPtr]::Zero)
    [LanguageTransitionProbe]::keybd_event(0x0d, 0, 2, [UIntPtr]::Zero)
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        $wizard = Find-TestWindow $process.Id 'SIDEY language transition test Setup'
        $visible = $wizard -ne [IntPtr]::Zero -and [LanguageTransitionProbe]::IsWindowVisible($wizard)
        $foreground = $visible -and [LanguageTransitionProbe]::GetForegroundWindow() -eq $wizard
        if (-not $foreground) { Start-Sleep -Milliseconds 100 }
    } while (-not $foreground -and [DateTime]::UtcNow -lt $deadline)
    if (-not $foreground -or [LanguageTransitionProbe]::IsIconic($wizard)) {
        throw "Installer did not become visible and foreground after language selection (visible=$visible, foreground=$foreground)."
    }
    Write-Output 'NativeLanguageDialog=true; Languages=7; SystemFirst=true; InstallerLanguageTransition=true; WelcomeVisible=true; WelcomeForeground=true; Minimized=false'
}
finally {
    if ($helper) { Stop-Process -Id $helper.ProcessId -ErrorAction SilentlyContinue }
    if (-not $process.HasExited) { $process.Kill() }
    $process.Dispose()
}
