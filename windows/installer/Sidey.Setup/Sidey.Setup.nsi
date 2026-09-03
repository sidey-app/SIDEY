Unicode true

!ifndef APP_VERSION
  !error "APP_VERSION is required."
!endif
!ifndef APP_FILE_VERSION
  !error "APP_FILE_VERSION is required."
!endif
!ifndef OUTPUT_DIR
  !error "OUTPUT_DIR is required."
!endif
!ifndef PUBLISH_DIR
  !error "PUBLISH_DIR is required."
!endif
!ifndef PAYLOAD_INSTALL_INCLUDE
  !error "PAYLOAD_INSTALL_INCLUDE is required."
!endif
!ifndef PAYLOAD_UNINSTALL_INCLUDE
  !error "PAYLOAD_UNINSTALL_INCLUDE is required."
!endif

!define PRODUCT_NAME "SIDEY"
!define PRODUCT_PUBLISHER "SIDEY"
!define PRODUCT_REGISTRY_KEY "Software\SIDEY\Installer"
!define PRODUCT_UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\SIDEY"
!define LEGACY_MSI_UPGRADE_CODE "{E744D02B-C3CF-41CE-A4C9-9BA1EB10C6B9}"

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "WordFunc.nsh"
!include "nsDialogs.nsh"
!include "WinMessages.nsh"

!insertmacro VersionCompare

Name "${PRODUCT_NAME} ${APP_VERSION}"
OutFile "${OUTPUT_DIR}\SIDEY-Setup.exe"
InstallDir "$PROGRAMFILES64\SIDEY"
InstallDirRegKey HKLM "${PRODUCT_REGISTRY_KEY}" "InstallLocation"
RequestExecutionLevel admin
ManifestDPIAware true
SetCompressor /SOLID lzma
SetCompressorDictSize 64
CRCCheck on
ShowInstDetails show
ShowUninstDetails show
BrandingText "SIDEY"
Icon "${PUBLISH_DIR}\Assets\Icons\SideyAppIcon.ico"
UninstallIcon "${PUBLISH_DIR}\Assets\Icons\SideyAppIcon.ico"
VIProductVersion "${APP_FILE_VERSION}"
VIAddVersionKey /LANG=1033 "ProductName" "SIDEY"
VIAddVersionKey /LANG=1033 "ProductVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=1033 "CompanyName" "SIDEY"
VIAddVersionKey /LANG=1033 "LegalCopyright" "Copyright (c) SIDEY"
VIAddVersionKey /LANG=1033 "FileDescription" "SIDEY Setup"
VIAddVersionKey /LANG=1033 "FileVersion" "${APP_FILE_VERSION}"

!define MUI_ABORTWARNING
!define MUI_ICON "${PUBLISH_DIR}\Assets\Icons\SideyAppIcon.ico"
!define MUI_UNICON "${PUBLISH_DIR}\Assets\Icons\SideyAppIcon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\SIDEY.exe"
!define MUI_FINISHPAGE_RUN_TEXT "$(LaunchSidey)"
!define MUI_LANGDLL_REGISTRY_ROOT "HKLM"
!define MUI_LANGDLL_REGISTRY_KEY "${PRODUCT_REGISTRY_KEY}"
!define MUI_LANGDLL_REGISTRY_VALUENAME "Language"

!insertmacro MUI_PAGE_WELCOME
Page custom MaintenancePageCreate
!define MUI_PAGE_CUSTOMFUNCTION_PRE DirectoryPagePre
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
UninstPage custom un.CleanupPageCreate un.CleanupPageLeave
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Korean"

SetFont /LANG=${LANG_ENGLISH} "Segoe UI" 9
SetFont /LANG=${LANG_KOREAN} "맑은 고딕" 9

LangString LaunchSidey ${LANG_ENGLISH} "Launch SIDEY"
LangString LaunchSidey ${LANG_KOREAN} "SIDEY 실행"
LangString MaintenanceTitle ${LANG_ENGLISH} "SIDEY is already installed"
LangString MaintenanceTitle ${LANG_KOREAN} "SIDEY가 이미 설치되어 있습니다"
LangString MaintenanceSubtitle ${LANG_ENGLISH} "Choose what you want Setup to do."
LangString MaintenanceSubtitle ${LANG_KOREAN} "설치 프로그램에서 수행할 작업을 선택하세요."
LangString MaintenanceDescription ${LANG_ENGLISH} "This version of SIDEY is already installed. You can repair the installation or remove SIDEY."
LangString MaintenanceDescription ${LANG_KOREAN} "같은 버전의 SIDEY가 이미 설치되어 있습니다. 설치를 복구하거나 SIDEY를 삭제할 수 있습니다."
LangString RepairAction ${LANG_ENGLISH} "Repair"
LangString RepairAction ${LANG_KOREAN} "복구"
LangString RemoveAction ${LANG_ENGLISH} "Uninstall"
LangString RemoveAction ${LANG_KOREAN} "삭제"
LangString CloseAction ${LANG_ENGLISH} "Close"
LangString CloseAction ${LANG_KOREAN} "닫기"
LangString DowngradeBlocked ${LANG_ENGLISH} "A newer version of SIDEY is already installed. Uninstall it before installing ${APP_VERSION}."
LangString DowngradeBlocked ${LANG_KOREAN} "더 새로운 버전의 SIDEY가 이미 설치되어 있습니다. ${APP_VERSION} 버전을 설치하려면 먼저 삭제해 주세요."
LangString LegacyMigrationFailed ${LANG_ENGLISH} "The previous SIDEY MSI could not be removed. Setup cannot continue. Error code: $0"
LangString LegacyMigrationFailed ${LANG_KOREAN} "이전 SIDEY MSI를 삭제하지 못해 설치를 계속할 수 없습니다. 오류 코드: $0"
LangString LegacyMigrationRestart ${LANG_ENGLISH} "Windows must restart to finish removing the previous SIDEY MSI. Restart Windows, then run Setup again."
LangString LegacyMigrationRestart ${LANG_KOREAN} "이전 SIDEY MSI 삭제를 마치려면 Windows를 다시 시작해야 합니다. 다시 시작한 뒤 설치 프로그램을 다시 실행해 주세요."
LangString ExistingRemovalFailed ${LANG_ENGLISH} "The existing SIDEY installation could not be prepared for this installation. Error code: $0"
LangString ExistingRemovalFailed ${LANG_KOREAN} "기존 SIDEY 설치를 새 설치용으로 정리하지 못했습니다. 오류 코드: $0"
LangString CleanupTitle ${LANG_ENGLISH} "Remove optional SIDEY data"
LangString CleanupTitle ${LANG_KOREAN} "SIDEY 선택 데이터 삭제"
LangString CleanupSubtitle ${LANG_ENGLISH} "Choose the current-user data to remove."
LangString CleanupSubtitle ${LANG_KOREAN} "함께 삭제할 현재 사용자 데이터를 선택하세요."
LangString CleanupDescription ${LANG_ENGLISH} "The SIDEY application will be removed. The following items are kept unless you select them."
LangString CleanupDescription ${LANG_KOREAN} "SIDEY 앱은 삭제됩니다. 아래 항목은 선택한 경우에만 함께 삭제됩니다."
LangString DeleteLocalData ${LANG_ENGLISH} "Delete settings and logs (%LOCALAPPDATA%\SIDEY)"
LangString DeleteLocalData ${LANG_KOREAN} "설정과 로그 삭제 (%LOCALAPPDATA%\SIDEY)"
LangString DeleteCredentials ${LANG_ENGLISH} "Delete saved SIDEY sign-in credentials"
LangString DeleteCredentials ${LANG_KOREAN} "저장된 SIDEY 로그인 자격 증명 삭제"
LangString CleanupFailed ${LANG_ENGLISH} "Some selected current-user data could not be removed. Error code: $0"
LangString CleanupFailed ${LANG_KOREAN} "선택한 현재 사용자 데이터 일부를 삭제하지 못했습니다. 오류 코드: $0"

Var InstallState
Var InstalledVersion
Var VersionResult
Var MaintenanceDialog
Var RepairButton
Var RemoveButton
Var CloseButton
Var DeleteLocalDataCheckbox
Var DeleteCredentialsCheckbox
Var DeleteLocalData
Var DeleteCredentials
Var HasNsisInstall

Function .onInit
  SetRegView 64
  SetShellVarContext all
  !insertmacro MUI_LANGDLL_DISPLAY

  StrCpy $InstallState "fresh"
  StrCpy $HasNsisInstall "false"
  ReadRegStr $InstalledVersion HKLM "${PRODUCT_REGISTRY_KEY}" "InstalledVersion"
  ReadRegStr $0 HKLM "${PRODUCT_REGISTRY_KEY}" "InstallLocation"
  ${If} $0 != ""
    StrCpy $INSTDIR $0
    StrCpy $HasNsisInstall "true"
  ${EndIf}

  ${If} $InstalledVersion != ""
    ${VersionCompare} $InstalledVersion "${APP_VERSION}" $VersionResult
    ${If} $VersionResult == 1
      MessageBox MB_OK|MB_ICONSTOP "$(DowngradeBlocked)"
      Quit
    ${ElseIf} $VersionResult == 0
      StrCpy $InstallState "same"
    ${Else}
      StrCpy $InstallState "upgrade"
    ${EndIf}
  ${EndIf}
FunctionEnd

Function MaintenancePageCreate
  ${If} $InstallState != "same"
    Abort
  ${EndIf}

  !insertmacro MUI_HEADER_TEXT "$(MaintenanceTitle)" "$(MaintenanceSubtitle)"
  nsDialogs::Create 1018
  Pop $MaintenanceDialog
  ${If} $MaintenanceDialog == error
    Abort
  ${EndIf}

  ${NSD_CreateLabel} 0 8u 100% 34u "$(MaintenanceDescription)"
  Pop $0
  ${NSD_CreateButton} 0 57u 31% 22u "$(RepairAction)"
  Pop $RepairButton
  ${NSD_OnClick} $RepairButton SelectRepair
  ${NSD_CreateButton} 34.5% 57u 31% 22u "$(RemoveAction)"
  Pop $RemoveButton
  ${NSD_OnClick} $RemoveButton SelectRemove
  ${NSD_CreateButton} 69% 57u 31% 22u "$(CloseAction)"
  Pop $CloseButton
  ${NSD_OnClick} $CloseButton SelectClose

  GetDlgItem $0 $HWNDPARENT 1
  ShowWindow $0 ${SW_HIDE}
  GetDlgItem $0 $HWNDPARENT 3
  ShowWindow $0 ${SW_HIDE}
  GetDlgItem $0 $HWNDPARENT 2
  ShowWindow $0 ${SW_HIDE}
  ${NSD_SetFocus} $RepairButton
  nsDialogs::Show
FunctionEnd

Function RestoreNavigationButtons
  GetDlgItem $0 $HWNDPARENT 1
  ShowWindow $0 ${SW_SHOW}
  GetDlgItem $0 $HWNDPARENT 3
  ShowWindow $0 ${SW_SHOW}
  GetDlgItem $0 $HWNDPARENT 2
  ShowWindow $0 ${SW_SHOW}
FunctionEnd

Function SelectRepair
  StrCpy $InstallState "repair"
  Call RestoreNavigationButtons
  SendMessage $HWNDPARENT ${WM_COMMAND} 1 0
FunctionEnd

Function SelectRemove
  StrCpy $InstallState "remove"
  Call RestoreNavigationButtons
  SendMessage $HWNDPARENT ${WM_COMMAND} 1 0
FunctionEnd

Function SelectClose
  StrCpy $InstallState "close"
  Call RestoreNavigationButtons
  SendMessage $HWNDPARENT ${WM_COMMAND} 1 0
FunctionEnd

Function DirectoryPagePre
  ${If} $InstallState == "remove"
    HideWindow
    ExecWait '"$INSTDIR\Uninstall.exe"'
    Quit
  ${ElseIf} $InstallState == "close"
    HideWindow
    Quit
  ${ElseIf} $InstallState == "upgrade"
  ${OrIf} $InstallState == "repair"
    Abort
  ${EndIf}
FunctionEnd

Function StopSideyProcesses
  nsExec::ExecToLog '"$SYSDIR\taskkill.exe" /IM SIDEY.exe /F'
  Pop $0
  nsExec::ExecToLog '"$SYSDIR\taskkill.exe" /IM SIDEY.Host.exe /F'
  Pop $0
FunctionEnd

Section "SIDEY" MainSection
  SetRegView 64
  SetShellVarContext all
  SetOverwrite on
  Call StopSideyProcesses

  ${If} $HasNsisInstall == "true"
    StrCpy $0 2
    IfFileExists "$INSTDIR\Uninstall.exe" 0 existing_uninstall_failed
    ExecWait '"$INSTDIR\Uninstall.exe" /S' $0
    ${If} $0 != 0
      Goto existing_uninstall_failed
    ${EndIf}
  ${EndIf}
  Goto existing_uninstall_done

  existing_uninstall_failed:
    MessageBox MB_OK|MB_ICONSTOP "$(ExistingRemovalFailed)"
    Abort

  existing_uninstall_done:

  InitPluginsDir
  File /oname=$PLUGINSDIR\SideyLegacyMsiHelper.exe "${PUBLISH_DIR}\Uninstall.exe"
  ExecWait '"$PLUGINSDIR\SideyLegacyMsiHelper.exe" --uninstall-legacy-msi' $0
  ${If} $0 == 3010
    MessageBox MB_OK|MB_ICONSTOP "$(LegacyMigrationRestart)"
    Abort
  ${ElseIf} $0 != 0
  ${AndIf} $0 != 1605
    MessageBox MB_OK|MB_ICONSTOP "$(LegacyMigrationFailed)"
    Abort
  ${EndIf}

  !include "${PAYLOAD_INSTALL_INCLUDE}"
  SetOutPath "$INSTDIR\Runtime"
  File /oname=SIDEY.UninstallHelper.exe "${PUBLISH_DIR}\Uninstall.exe"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$SMPROGRAMS\SIDEY"
  CreateShortcut "$SMPROGRAMS\SIDEY\SIDEY.lnk" "$INSTDIR\SIDEY.exe" "" "$INSTDIR\Assets\Icons\SideyAppIcon.ico"
  CreateShortcut "$SMPROGRAMS\SIDEY\Uninstall SIDEY.lnk" "$INSTDIR\Uninstall.exe" "" "$INSTDIR\Assets\Icons\SideyAppIcon.ico"

  WriteRegStr HKLM "${PRODUCT_REGISTRY_KEY}" "InstalledVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${PRODUCT_REGISTRY_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "DisplayName" "SIDEY"
  WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\Assets\Icons\SideyAppIcon.ico"
  WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
  WriteRegDWORD HKLM "${PRODUCT_UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${PRODUCT_UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Function un.onInit
  SetRegView 64
  SetShellVarContext all
  !insertmacro MUI_UNGETLANGUAGE
  StrCpy $DeleteLocalData 0
  StrCpy $DeleteCredentials 0
FunctionEnd

Function un.CleanupPageCreate
  !insertmacro MUI_HEADER_TEXT "$(CleanupTitle)" "$(CleanupSubtitle)"
  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == error
    Abort
  ${EndIf}

  ${NSD_CreateLabel} 0 6u 100% 28u "$(CleanupDescription)"
  Pop $0
  ${NSD_CreateCheckbox} 0 48u 100% 12u "$(DeleteLocalData)"
  Pop $DeleteLocalDataCheckbox
  ${NSD_Uncheck} $DeleteLocalDataCheckbox
  ${NSD_CreateCheckbox} 0 72u 100% 12u "$(DeleteCredentials)"
  Pop $DeleteCredentialsCheckbox
  ${NSD_Uncheck} $DeleteCredentialsCheckbox
  nsDialogs::Show
FunctionEnd

Function un.CleanupPageLeave
  ${NSD_GetState} $DeleteLocalDataCheckbox $DeleteLocalData
  ${NSD_GetState} $DeleteCredentialsCheckbox $DeleteCredentials
FunctionEnd

Section "Uninstall"
  SetRegView 64
  SetShellVarContext all
  nsExec::ExecToLog '"$SYSDIR\taskkill.exe" /IM SIDEY.exe /F'
  Pop $0
  nsExec::ExecToLog '"$SYSDIR\taskkill.exe" /IM SIDEY.Host.exe /F'
  Pop $0

  ${If} $DeleteLocalData == ${BST_CHECKED}
    ExecWait '"$INSTDIR\Runtime\SIDEY.UninstallHelper.exe" --cleanup-local-data' $0
    ${If} $0 != 0
      MessageBox MB_OK|MB_ICONEXCLAMATION "$(CleanupFailed)"
    ${EndIf}
  ${EndIf}
  ${If} $DeleteCredentials == ${BST_CHECKED}
    ExecWait '"$INSTDIR\Runtime\SIDEY.UninstallHelper.exe" --cleanup-credentials' $0
    ${If} $0 != 0
      MessageBox MB_OK|MB_ICONEXCLAMATION "$(CleanupFailed)"
    ${EndIf}
  ${EndIf}

  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "SIDEY"
  Delete "$SMPROGRAMS\SIDEY\SIDEY.lnk"
  Delete "$SMPROGRAMS\SIDEY\Uninstall SIDEY.lnk"
  RMDir "$SMPROGRAMS\SIDEY"
  Delete "$INSTDIR\Runtime\SIDEY.UninstallHelper.exe"
  !include "${PAYLOAD_UNINSTALL_INCLUDE}"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR\Runtime"
  RMDir "$INSTDIR"
  DeleteRegKey HKLM "${PRODUCT_UNINSTALL_KEY}"
  DeleteRegKey HKLM "${PRODUCT_REGISTRY_KEY}"
SectionEnd
