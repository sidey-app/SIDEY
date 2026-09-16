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
!ifndef TERMS_LICENSE_FILE
  !error "TERMS_LICENSE_FILE is required."
!endif
!ifndef LANGUAGE_SELECTOR_EXE
  !error "LANGUAGE_SELECTOR_EXE is required."
!endif
!ifndef INSTALL_TRANSACTION_EXE
  !error "INSTALL_TRANSACTION_EXE is required."
!endif
!ifndef PREREQUISITE_INSTALLER_EXE
  !error "PREREQUISITE_INSTALLER_EXE is required."
!endif

!define PRODUCT_NAME "SIDEY"
!define PRODUCT_PUBLISHER "SIDEY"
!define PRODUCT_REGISTRY_KEY "Software\SIDEY\Installer"
!define PRODUCT_TRANSACTION_KEY "Software\SIDEY\InstallerTransaction"
!define PRODUCT_UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\SIDEY"
!define PRODUCT_PROTOCOL_KEY "Software\Classes\sidey"
!define LEGACY_MSI_UPGRADE_CODE "{E744D02B-C3CF-41CE-A4C9-9BA1EB10C6B9}"

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "WordFunc.nsh"
!include "FileFunc.nsh"
!include "nsDialogs.nsh"
!include "WinMessages.nsh"
!include "x64.nsh"

!insertmacro VersionCompare

Name "${PRODUCT_NAME} ${APP_VERSION}"
OutFile "${OUTPUT_DIR}\SIDEY-Setup.exe"
InstallDir "$PROGRAMFILES64\SIDEY"
InstallDirRegKey HKLM "${PRODUCT_REGISTRY_KEY}" "InstallLocation"
RequestExecutionLevel admin
ManifestDPIAware true
SetCompressor lzma
SetCompressorDictSize 8
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
!define MUI_WELCOMEFINISHPAGE_BITMAP "${__FILEDIR__}\SideyWelcome.bmp"
!define MUI_WELCOMEFINISHPAGE_BITMAP_STRETCH "FitControl"
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "$(LaunchSidey)"
!define MUI_FINISHPAGE_RUN_FUNCTION LaunchSideyAsDesktopUser
!define MUI_LANGDLL_REGISTRY_ROOT "HKLM"
!define MUI_LANGDLL_REGISTRY_KEY "${PRODUCT_REGISTRY_KEY}"
!define MUI_LANGDLL_REGISTRY_VALUENAME "Language"
!define MUI_CUSTOMFUNCTION_GUIINIT ShowInstallerAfterLanguageSelection

!insertmacro MUI_PAGE_WELCOME
Page custom MaintenancePageCreate
!define MUI_PAGE_HEADER_TEXT "$(TermsTitle)"
!define MUI_PAGE_HEADER_SUBTEXT "$(TermsSubtitle)"
!define MUI_PAGE_CUSTOMFUNCTION_PRE TermsPagePre
!define MUI_LICENSEPAGE_TEXT_TOP "$(TermsTop)"
!define MUI_LICENSEPAGE_CHECKBOX
!define MUI_LICENSEPAGE_CHECKBOX_TEXT "$(AcceptTerms)"
!insertmacro MUI_PAGE_LICENSE "${TERMS_LICENSE_FILE}"
!define MUI_PAGE_CUSTOMFUNCTION_PRE DirectoryPagePre
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
UninstPage custom un.CleanupPageCreate un.CleanupPageLeave
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Korean"
!insertmacro MUI_LANGUAGE "Japanese"
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "TradChinese"
!insertmacro MUI_LANGUAGE "Russian"
!insertmacro MUI_LANGUAGE "Ukrainian"

SetFont /LANG=${LANG_ENGLISH} "Segoe UI" 9
SetFont /LANG=${LANG_KOREAN} "맑은 고딕" 9
SetFont /LANG=${LANG_JAPANESE} "Yu Gothic UI" 9
SetFont /LANG=${LANG_SIMPCHINESE} "Microsoft YaHei UI" 9
SetFont /LANG=${LANG_TRADCHINESE} "Microsoft JhengHei UI" 9
SetFont /LANG=${LANG_RUSSIAN} "Segoe UI" 9
SetFont /LANG=${LANG_UKRAINIAN} "Segoe UI" 9

LangString LaunchSidey ${LANG_ENGLISH} "Launch SIDEY"
LangString LaunchSidey ${LANG_KOREAN} "SIDEY 실행"
LangString TermsTitle ${LANG_ENGLISH} "SIDEY Terms of Use"
LangString TermsTitle ${LANG_KOREAN} "SIDEY 이용약관"
LangString TermsSubtitle ${LANG_ENGLISH} "Review and accept the terms before installing SIDEY."
LangString TermsSubtitle ${LANG_KOREAN} "SIDEY를 설치하기 전에 약관을 확인하고 동의해 주세요."
LangString TermsTop ${LANG_ENGLISH} "Read the terms below. You must select the agreement checkbox to continue."
LangString TermsTop ${LANG_KOREAN} "아래 이용약관을 읽어 주세요. 계속하려면 동의 항목을 선택해야 합니다."
LangString AcceptTerms ${LANG_ENGLISH} "I have read and agree to the SIDEY Terms of Use."
LangString AcceptTerms ${LANG_KOREAN} "SIDEY 이용약관을 읽었으며 이에 동의합니다."
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
LangString DowngradeBlocked ${LANG_ENGLISH} "A newer version of SIDEY is already installed, so Setup made no changes. To install ${APP_VERSION}, uninstall the current SIDEY from Windows Settings > Apps, then run this Setup again."
LangString DowngradeBlocked ${LANG_KOREAN} "더 새로운 버전의 SIDEY가 이미 설치되어 있어 아무것도 변경하지 않았습니다. ${APP_VERSION} 버전을 설치하려면 Windows 설정 > 앱에서 현재 SIDEY를 제거한 뒤 이 설치 프로그램을 다시 실행하세요."
LangString LegacyMigrationManual ${LANG_ENGLISH} "A previous SIDEY MSI is installed, so Setup made no changes. Uninstall it from Windows Settings > Apps, then run this Setup again. Do not delete SIDEY installation files manually."
LangString LegacyMigrationManual ${LANG_KOREAN} "이전 SIDEY MSI가 설치되어 있어 아무것도 변경하지 않았습니다. Windows 설정 > 앱에서 제거한 뒤 이 설치 프로그램을 다시 실행하세요. SIDEY 설치 파일을 직접 삭제하지 마세요."
LangString ExistingRemovalFailed ${LANG_ENGLISH} "The existing uninstaller could not finish because required SIDEY files may be missing or in use. Run this Setup again and complete Repair, then run Setup again and choose Uninstall. If repair fails, restart Windows and try once more. If the problem continues, contact support and include error code: $0"
LangString ExistingRemovalFailed ${LANG_KOREAN} "필요한 SIDEY 설치 파일이 없거나 사용 중일 수 있어 기존 제거 프로그램을 완료하지 못했습니다. 이 설치 프로그램을 다시 실행해 복구를 먼저 완료한 뒤, 다시 실행하여 삭제를 선택해 주세요. 복구에 실패하면 Windows를 다시 시작하고 한 번 더 시도해 주세요. 그래도 해결되지 않으면 오류 코드 $0를 적어 문의해 주세요."
LangString PrerequisitesStatus ${LANG_ENGLISH} "Checking required runtimes; missing runtimes will be downloaded from Microsoft..."
LangString PrerequisitesStatus ${LANG_KOREAN} "필수 런타임을 확인하고 있습니다. 없는 런타임은 Microsoft에서 다운로드합니다..."
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
LangString CleanupFailed ${LANG_ENGLISH} "SIDEY removal will continue, but the following current-user items could not be removed. The listed error code belongs to that item:$\r$\n$CleanupFailureDetails"
LangString CleanupFailed ${LANG_KOREAN} "SIDEY 제거는 계속되지만 다음 현재 사용자 항목을 삭제하지 못했습니다. 표시된 오류 코드는 해당 항목의 코드입니다:$\r$\n$CleanupFailureDetails"
LangString CleanupLocalDataFailure ${LANG_ENGLISH} "- Settings and logs (%LOCALAPPDATA%\SIDEY), error code: $0"
LangString CleanupLocalDataFailure ${LANG_KOREAN} "- 설정과 로그 (%LOCALAPPDATA%\SIDEY), 오류 코드: $0"
LangString CleanupCredentialsFailure ${LANG_ENGLISH} "- Saved SIDEY sign-in credentials, error code: $0"
LangString CleanupCredentialsFailure ${LANG_KOREAN} "- 저장된 SIDEY 로그인 자격 증명, 오류 코드: $0"
LangString CleanupStartupFailure ${LANG_ENGLISH} "- SIDEY startup entry, error code: $0"
LangString CleanupStartupFailure ${LANG_KOREAN} "- SIDEY 시작프로그램 항목, 오류 코드: $0"
LangString LaunchFailed ${LANG_ENGLISH} "SIDEY was installed successfully, but it could not be started as the desktop user. Restart Windows, then start SIDEY from the Start menu. If it still does not start, contact support with error code: $0"
LangString LaunchFailed ${LANG_KOREAN} "SIDEY 설치는 완료했지만 데스크톱 사용자 권한으로 실행하지 못했습니다. Windows를 다시 시작한 뒤 시작 메뉴에서 SIDEY를 실행하세요. 계속 실행되지 않으면 오류 코드 $0을 포함해 고객지원에 문의하세요."
LangString TransactionFailed ${LANG_ENGLISH} "SIDEY installation was not completed. If SIDEY was already installed, the previous installation was kept or restored. Error code: $0"
LangString TransactionFailed ${LANG_KOREAN} "SIDEY 설치를 완료하지 못했습니다. SIDEY가 이미 설치되어 있었다면 이전 설치를 유지하거나 복원했습니다. 오류 코드: $0"
LangString TransactionStateUnknown ${LANG_ENGLISH} "Setup could not confirm the final SIDEY installation state. Restart Windows, then run the latest SIDEY Setup again. If Setup offers Repair, complete it. Do not delete installation files manually. If Setup cannot continue, contact support with error code: $0"
LangString TransactionStateUnknown ${LANG_KOREAN} "SIDEY의 최종 설치 상태를 확인하지 못했습니다. Windows를 다시 시작한 뒤 최신 SIDEY 설치 프로그램을 다시 실행하세요. 복구가 표시되면 완료하세요. 설치 파일을 직접 삭제하지 마세요. 설치를 계속할 수 없으면 오류 코드 $0을 포함해 고객지원에 문의하세요."
LangString TransactionRecoveryFailed ${LANG_ENGLISH} "Setup could not recover an interrupted SIDEY installation. Restart Windows, then run the latest SIDEY Setup again. Do not delete installation files manually. If the problem continues, contact support with error code: $0"
LangString TransactionRecoveryFailed ${LANG_KOREAN} "중단된 SIDEY 설치를 복구하지 못했습니다. Windows를 다시 시작한 뒤 최신 SIDEY 설치 프로그램을 다시 실행하세요. 설치 파일을 직접 삭제하지 마세요. 문제가 계속되면 오류 코드 $0을 포함해 고객지원에 문의하세요."
LangString UninstallPreflightFailed ${LANG_ENGLISH} "SIDEY could not prepare for removal, so no uninstall changes were made. Close SIDEY, restart Windows, and try again. If the problem continues, contact support with error code: $0"
LangString UninstallPreflightFailed ${LANG_KOREAN} "SIDEY 제거를 준비하지 못해 제거 작업을 시작하지 않았습니다. SIDEY를 종료하고 Windows를 다시 시작한 뒤 다시 시도하세요. 문제가 계속되면 오류 코드 $0을 포함해 고객지원에 문의하세요."
LangString UninstallStateUnknown ${LANG_ENGLISH} "Setup could not confirm the final SIDEY removal state. Restart Windows, then run the latest SIDEY Setup again. Do not delete installation files manually. If the problem continues, contact support with error code: $0"
LangString UninstallStateUnknown ${LANG_KOREAN} "SIDEY의 최종 제거 상태를 확인하지 못했습니다. Windows를 다시 시작한 뒤 최신 SIDEY 설치 프로그램을 다시 실행하세요. 설치 파일을 직접 삭제하지 마세요. 문제가 계속되면 오류 코드 $0을 포함해 고객지원에 문의하세요."
LangString SetupAlreadyRunning ${LANG_ENGLISH} "Another SIDEY Setup or uninstaller is already running. Close it before continuing."
LangString SetupAlreadyRunning ${LANG_KOREAN} "다른 SIDEY 설치 프로그램 또는 제거 프로그램이 실행 중입니다. 먼저 종료한 뒤 다시 시도해 주세요."
LangString SetupInitializationFailed ${LANG_ENGLISH} "SIDEY Setup could not initialize the installation lock. Restart Windows and run Setup again. If the problem continues, contact support with error code: $1"
LangString SetupInitializationFailed ${LANG_KOREAN} "SIDEY 설치 잠금을 초기화하지 못했습니다. Windows를 다시 시작한 뒤 설치 프로그램을 다시 실행하세요. 문제가 계속되면 오류 코드 $1을 포함해 고객지원에 문의하세요."
LangString CleanupPending ${LANG_ENGLISH} "SIDEY was installed, but the previous-version backup could not be removed. Setup will retry cleanup next time."
LangString CleanupPending ${LANG_KOREAN} "SIDEY를 설치했지만 이전 버전 백업을 정리하지 못했습니다. 다음 설치 실행 때 정리를 다시 시도합니다."

!include "${__FILEDIR__}\Languages.nsh"
!include "${__FILEDIR__}\InstallerErrors.nsh"

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
Var CleanupFailureDetails
Var StagingDirectory
Var RollbackDirectory
Var SetupMutexHandle

!macro AcquireSetupMutex HANDLE
  System::Call 'kernel32::CreateMutexW(p0, i0, w "Global\SIDEY.Setup.InstallTransaction") p.r0 ?e'
  Pop $1
  StrCpy ${HANDLE} $0
  ${If} $1 == 183
    ${If} ${HANDLE} != 0
      System::Call 'kernel32::CloseHandle(p ${HANDLE})'
      StrCpy ${HANDLE} 0
    ${EndIf}
    MessageBox MB_OK|MB_ICONSTOP "$(SetupAlreadyRunning)" /SD IDOK
    Abort
  ${ElseIf} ${HANDLE} == 0
    SetErrorLevel $1
    MessageBox MB_OK|MB_ICONSTOP "$(SetupInitializationFailed)" /SD IDOK
    Abort
  ${EndIf}
!macroend

!macro RunInstallTransaction ACTION RESULT
  ClearErrors
  ExecWait '"$PLUGINSDIR\Sidey.InstallTransaction.exe" --action ${ACTION} --install-directory "$INSTDIR" --staging-directory "$StagingDirectory" --rollback-directory "$RollbackDirectory" --version "${APP_VERSION}"' ${RESULT}
  ${If} ${Errors}
    StrCpy ${RESULT} 5
  ${EndIf}
!macroend

Function .onInit
  SetRegView 64
  SetShellVarContext all
  Call SelectInstallerLanguage
  !insertmacro AcquireSetupMutex $SetupMutexHandle
  Call InitializeInstallerErrorHandling

  StrCpy $InstallState "fresh"
  ReadRegStr $0 HKLM "${PRODUCT_TRANSACTION_KEY}" "InstallLocation"
  ${If} $0 == ""
    ReadRegStr $0 HKLM "${PRODUCT_REGISTRY_KEY}" "InstallLocation"
  ${EndIf}
  ${If} $0 != ""
    StrCpy $INSTDIR $0
  ${EndIf}

  ; Recovery must precede installed-version classification. A process can stop
  ; after writing the new version but before committing its payload.
  Call InitializeInstallTransaction
  Call PrepareInstallerHelpers
  !insertmacro RunInstallTransaction "Recover" $0
  ${If} $0 != 0
    StrCpy $1 $0
    Call ResetInstallerError
    StrCpy $0 $1
    StrCpy $InstallerErrorNativeCode $1
    StrCpy $InstallerErrorExitCode $1
    StrCpy $InstallerErrorSource "TRANSACTION"
    StrCpy $InstallerErrorStage "RECOVER"
    StrCpy $InstallerErrorSymbol "TRANSACTION_RECOVERY_FAILED"
    StrCpy $InstallerErrorTarget "$(InstallerComponentInstallationState)"
    StrCpy $InstallerErrorCommand "Sidey.InstallTransaction.exe --action Recover"
    StrCpy $InstallerErrorMessage "$(TransactionRecoveryFailed)"
    Call ShowLifecycleError
    SetErrorLevel 1
    Abort
  ${EndIf}

  ReadRegStr $InstalledVersion HKLM "${PRODUCT_REGISTRY_KEY}" "InstalledVersion"
  ReadRegStr $0 HKLM "${PRODUCT_REGISTRY_KEY}" "InstallLocation"
  ${If} $0 != ""
    StrCpy $INSTDIR $0
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

Function ReleaseSetupMutex
  ${If} $SetupMutexHandle != 0
    System::Call 'kernel32::CloseHandle(p $SetupMutexHandle)'
    StrCpy $SetupMutexHandle 0
  ${EndIf}
FunctionEnd

Function TermsPagePre
  ${If} $InstallState == "remove"
    HideWindow
    ; Hand ownership to the installed uninstaller, which acquires the same
    ; machine-wide mutex before it changes transaction or installation state.
    Call ReleaseSetupMutex
    ClearErrors
    ExecWait '"$INSTDIR\Uninstall.exe"' $0
    ${If} ${Errors}
      StrCpy $0 5
    ${EndIf}
    ${If} $0 != 0
      StrCpy $1 $0
      Call ResetInstallerError
      StrCpy $0 $1
      StrCpy $InstallerErrorNativeCode $1
      StrCpy $InstallerErrorExitCode $1
      StrCpy $InstallerErrorSource "UNINSTALLER"
      StrCpy $InstallerErrorStage "UNINSTALL"
      StrCpy $InstallerErrorSymbol "EXISTING_REMOVAL_FAILED"
      StrCpy $InstallerErrorTarget "$(InstallerComponentRemoval)"
      StrCpy $InstallerErrorCommand "$INSTDIR\Uninstall.exe"
      StrCpy $InstallerErrorMessage "$(ExistingRemovalFailed)"
      Call ShowLifecycleError
      SetErrorLevel 1
    ${EndIf}
    Quit
  ${ElseIf} $InstallState == "close"
    HideWindow
    Quit
  ${ElseIf} $InstallState == "repair"
    Abort
  ${EndIf}
FunctionEnd

Function DirectoryPagePre
  ${If} $InstallState == "upgrade"
  ${OrIf} $InstallState == "repair"
    Abort
  ${EndIf}
FunctionEnd

Function StopSideyProcesses
  ClearErrors
  ExecWait '"$PLUGINSDIR\Sidey.SetupSupport.exe" --stop-sidey-processes' $0
  ${If} ${Errors}
    StrCpy $0 5
  ${EndIf}
FunctionEnd

Function InitializeInstallTransaction
  System::Call 'kernel32::GetCurrentProcessId() i.r0'
  StrCpy $StagingDirectory "$INSTDIR.sidey-staging-$0"
  StrCpy $RollbackDirectory "$INSTDIR.sidey-rollback"
FunctionEnd

Function RollbackInstallTransaction
  ${If} $StagingDirectory == ""
    StrCpy $0 0
    Return
  ${EndIf}
  !insertmacro RunInstallTransaction "Rollback" $0
FunctionEnd

Function LaunchSideyAsDesktopUser
  ClearErrors
  ExecWait '"$INSTDIR\Runtime\SIDEY.UninstallHelper.exe" --launch-sidey-as-desktop-user' $0
  ${If} ${Errors}
    StrCpy $0 5
  ${EndIf}
  ${If} $0 != 0
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(LaunchFailed)" /SD IDOK
  ${EndIf}
FunctionEnd

Function SelectInstallerLanguage
  ; Select before NSIS initializes its language tables. LangDLL sorts its combo
  ; internally, so reuse its native template with explicitly ordered insertions.
  InitPluginsDir
  File /oname=$PLUGINSDIR\Sidey.SetupLanguage.exe "${LANGUAGE_SELECTOR_EXE}"
  ReadRegStr $0 HKLM "${PRODUCT_REGISTRY_KEY}" "Language"
  System::Call 'kernel32::GetCurrentProcessId() i.r2'
  ClearErrors
  ${If} ${Silent}
    ExecWait '"$PLUGINSDIR\Sidey.SetupLanguage.exe" "$0" $2 --silent' $1
  ${Else}
    ExecWait '"$PLUGINSDIR\Sidey.SetupLanguage.exe" "$0" $2' $1
  ${EndIf}
  ${If} ${Errors}
  ${OrIf} $1 == 1
    SetErrorLevel 1
    MessageBox MB_OK|MB_ICONSTOP "$(LanguageSelectionFailed)" /SD IDOK
    Abort
  ${ElseIf} $1 == 0
    SetErrorLevel 1602
    Abort
  ${EndIf}
  StrCpy $LANGUAGE $1
FunctionEnd

Function ShowInstallerAfterLanguageSelection
  ; The selector grants this process foreground access before closing. Wait for
  ; the NSIS window to exist before restoring and activating it.
  BringToFront
FunctionEnd

Function PrepareInstallerHelpers
  InitPluginsDir
  ; Updates can inherit the app host's Runtime working directory. Release it in
  ; the installer itself before launching any helper or removing the old app.
  SetOutPath "$PLUGINSDIR"
  File /oname=$PLUGINSDIR\Sidey.InstallTransaction.exe "${INSTALL_TRANSACTION_EXE}"
  File /oname=$PLUGINSDIR\Sidey.PrerequisiteInstaller.exe "${PREREQUISITE_INSTALLER_EXE}"
  File /oname=$PLUGINSDIR\Sidey.SetupSupport.exe "${PUBLISH_DIR}\Uninstall.exe"
  File /oname=$PLUGINSDIR\prerequisites.json "${__FILEDIR__}\prerequisites.json"
FunctionEnd

Function EnsurePrerequisites
  Call PrepareInstallerHelpers
  Call ResetInstallerError
  StrCpy $InstallerErrorSource "PREREQUISITE"
  StrCpy $InstallerErrorStage "INSTALL"
  StrCpy $InstallerErrorTarget "SIDEY required runtimes"
  StrCpy $InstallerErrorCommand "Install-SideyPrerequisites"
  DetailPrint "$(PrerequisitesStatus)"
  ClearErrors
  ExecWait '"$PLUGINSDIR\Sidey.PrerequisiteInstaller.exe" --desktop-user-runner "$PLUGINSDIR\Sidey.SetupSupport.exe" --config "$PLUGINSDIR\prerequisites.json" --download-directory "$PLUGINSDIR" --result-path "$InstallerErrorResultPath" --log-path "$InstallerErrorLogPath" --installer-version "${APP_VERSION}"' $0
  ${If} ${Errors}
    StrCpy $0 5
  ${EndIf}
  StrCpy $InstallerErrorExitCode $0
  StrCpy $InstallerErrorNativeCode $0
  Call LoadInstallerResult
  ${If} $InstallerErrorStatus == "SUCCESS"
  ${AndIf} $0 == 0
    Return
  ${ElseIf} $InstallerErrorStatus == "SUCCESS_REBOOT_REQUIRED"
    SetErrorLevel 3010
    Call ShowInstallerError
    Abort
  ${ElseIf} $InstallerErrorCategory == "USER_CANCELLED"
    SetErrorLevel 1602
    Call ShowInstallerError
    Abort
  ${Else}
    SetErrorLevel 1
    Call ShowInstallerError
    Abort
  ${EndIf}
FunctionEnd

Section "SIDEY" MainSection
  SetRegView 64
  SetShellVarContext all
  SetOverwrite on
  Call EnsurePrerequisites
  Call InitializeInstallTransaction
  !insertmacro RunInstallTransaction "Prepare" $0
  ${If} $0 != 0
    StrCpy $1 $0
    Call ResetInstallerError
    StrCpy $0 $1
    StrCpy $InstallerErrorSource "TRANSACTION"
    StrCpy $InstallerErrorStage "PREPARE"
    StrCpy $InstallerErrorTarget "$(InstallerComponentInstallation)"
    StrCpy $InstallerErrorCommand "Sidey.InstallTransaction.exe --action Prepare"
    Goto transaction_failed
  ${EndIf}

  !include "${PAYLOAD_INSTALL_INCLUDE}"
  SetOutPath "$StagingDirectory\Runtime"
  ClearErrors
  File /oname=SIDEY.UninstallHelper.exe "${PUBLISH_DIR}\Uninstall.exe"
  IfErrors payload_stage_failed
  ClearErrors
  WriteUninstaller "$StagingDirectory\Uninstall.exe"
  IfErrors payload_stage_failed
  ; Release the staging tree as this process's working directory before rename.
  SetOutPath "$PLUGINSDIR"

  ; Keep the previous live install available until the full replacement payload
  ; is staged and validated. Downtime starts only after staging succeeds.
  ClearErrors
  ExecWait '"$PLUGINSDIR\Sidey.SetupSupport.exe" --detect-legacy-msi' $0
  ${If} ${Errors}
    StrCpy $0 5
    Goto legacy_detection_failed
  ${ElseIf} $0 == 0
    Call RollbackInstallTransaction
    ${If} $0 != 0
      Goto transaction_state_unknown
    ${EndIf}
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(LegacyMigrationManual)" /SD IDOK
    Abort
  ${ElseIf} $0 != 0
  ${AndIf} $0 != 1605
    Goto legacy_detection_failed
  ${EndIf}

  Call StopSideyProcesses
  ${If} $0 != 0
    StrCpy $1 $0
    Call ResetInstallerError
    StrCpy $0 $1
    StrCpy $InstallerErrorSource "PROCESS"
    StrCpy $InstallerErrorStage "PREFLIGHT"
    StrCpy $InstallerErrorTarget "$(InstallerComponentProcesses)"
    StrCpy $InstallerErrorCommand "Sidey.SetupSupport.exe --stop-sidey-processes"
    Goto registration_rollback_failed
  ${EndIf}

  !insertmacro RunInstallTransaction "Activate" $0
  ${If} $0 != 0
    StrCpy $1 $0
    Call ResetInstallerError
    StrCpy $0 $1
    StrCpy $InstallerErrorSource "TRANSACTION"
    StrCpy $InstallerErrorStage "ACTIVATE"
    StrCpy $InstallerErrorTarget "$(InstallerComponentInstallation)"
    StrCpy $InstallerErrorCommand "Sidey.InstallTransaction.exe --action Activate"
    Goto transaction_failed
  ${EndIf}

  !insertmacro RunInstallTransaction "BeginRegistration" $0
  ${If} $0 != 0
    StrCpy $1 $0
    Call ResetInstallerError
    StrCpy $0 $1
    StrCpy $InstallerErrorSource "TRANSACTION"
    StrCpy $InstallerErrorStage "BEGIN_REGISTRATION"
    StrCpy $InstallerErrorTarget "$(InstallerComponentRegistration)"
    StrCpy $InstallerErrorCommand "Sidey.InstallTransaction.exe --action BeginRegistration"
    Goto registration_rollback_failed
  ${EndIf}

  ClearErrors
  CreateDirectory "$SMPROGRAMS\SIDEY"
  CreateShortcut "$SMPROGRAMS\SIDEY\SIDEY.lnk" "$INSTDIR\SIDEY.exe" "" "$INSTDIR\Assets\Icons\SideyAppIcon.ico"
  CreateShortcut "$SMPROGRAMS\SIDEY\Uninstall SIDEY.lnk" "$INSTDIR\Uninstall.exe" "" "$INSTDIR\Assets\Icons\SideyAppIcon.ico"

  WriteRegStr HKLM "${PRODUCT_PROTOCOL_KEY}" "" "URL:SIDEY authentication callback"
  WriteRegStr HKLM "${PRODUCT_PROTOCOL_KEY}" "URL Protocol" ""
  WriteRegStr HKLM "${PRODUCT_PROTOCOL_KEY}\DefaultIcon" "" "$INSTDIR\Assets\Icons\SideyAppIcon.ico"
  WriteRegStr HKLM "${PRODUCT_PROTOCOL_KEY}\shell\open\command" "" '$\"$INSTDIR\SIDEY.exe$\" $\"%1$\"'

  WriteRegStr HKLM "${PRODUCT_REGISTRY_KEY}" "Language" $LANGUAGE
  WriteRegStr HKLM "${PRODUCT_REGISTRY_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "DisplayName" "SIDEY"
  WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\Assets\Icons\SideyAppIcon.ico"
  WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
  WriteRegDWORD HKLM "${PRODUCT_UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${PRODUCT_UNINSTALL_KEY}" "NoRepair" 1
  WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${PRODUCT_REGISTRY_KEY}" "InstalledVersion" "${APP_VERSION}"
  IfErrors registration_failed

  !insertmacro RunInstallTransaction "Commit" $0
  ${If} $0 != 0
    StrCpy $1 $0
    Call ResetInstallerError
    StrCpy $0 $1
    StrCpy $InstallerErrorSource "TRANSACTION"
    StrCpy $InstallerErrorStage "COMMIT"
    StrCpy $InstallerErrorTarget "$(InstallerComponentRegistration)"
    StrCpy $InstallerErrorCommand "Sidey.InstallTransaction.exe --action Commit"
    Goto registration_rollback_failed
  ${EndIf}

  !insertmacro RunInstallTransaction "Complete" $0
  ${If} $0 != 0
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(CleanupPending)" /SD IDOK
  ${EndIf}
  Goto install_complete

  payload_stage_failed:
    StrCpy $1 5
    Call ResetInstallerError
    StrCpy $InstallerErrorSource "FILESYSTEM"
    StrCpy $InstallerErrorStage "STAGE"
    StrCpy $InstallerErrorTarget "$(InstallerComponentPayload)"
    StrCpy $InstallerErrorCommand "Stage SIDEY application files"
    Call RollbackInstallTransaction
    ${If} $0 != 0
      Goto transaction_state_unknown
    ${EndIf}
    StrCpy $0 $1
    Goto transaction_failed

  registration_failed:
    StrCpy $0 5
    Call ResetInstallerError
    StrCpy $InstallerErrorSource "REGISTRY"
    StrCpy $InstallerErrorStage "REGISTER"
    StrCpy $InstallerErrorTarget "$(InstallerComponentRegistration)"
    StrCpy $InstallerErrorCommand "Register SIDEY shortcuts and Windows metadata"

  registration_rollback_failed:
    StrCpy $1 $0
    Call RollbackInstallTransaction
    ${If} $0 != 0
      Goto transaction_state_unknown
    ${EndIf}
    StrCpy $0 $1
    Goto transaction_failed

  legacy_detection_failed:
    StrCpy $1 $0
    Call RollbackInstallTransaction
    ${If} $0 != 0
      Goto transaction_state_unknown
    ${EndIf}
    StrCpy $0 $1
    Call ResetInstallerError
    StrCpy $InstallerErrorNativeCode $0
    StrCpy $InstallerErrorExitCode $0
    StrCpy $InstallerErrorSource "MSI"
    StrCpy $InstallerErrorStage "DETECT"
    StrCpy $InstallerErrorTarget "Legacy SIDEY MSI"
    StrCpy $InstallerErrorCommand "Sidey.SetupSupport.exe --detect-legacy-msi"
    Call NormalizeInstallerError
    Call ShowInstallerError
    Abort

  transaction_failed:
    StrCpy $1 $0
    StrCpy $0 $1
    StrCpy $InstallerErrorStatus "FAILED"
    StrCpy $InstallerErrorCategory "UNKNOWN_ERROR"
    StrCpy $InstallerErrorResultLoaded "false"
    StrCpy $InstallerErrorNativeCode $1
    StrCpy $InstallerErrorExitCode $1
    StrCpy $InstallerErrorSymbol "TRANSACTION_FAILED"
    StrCpy $InstallerErrorMessage "$(TransactionFailed)"
    Call ShowLifecycleError
    SetErrorLevel 1
    Abort

  transaction_state_unknown:
    StrCpy $1 $0
    Call ResetInstallerError
    StrCpy $0 $1
    StrCpy $InstallerErrorNativeCode $1
    StrCpy $InstallerErrorExitCode $1
    StrCpy $InstallerErrorSource "TRANSACTION"
    StrCpy $InstallerErrorStage "ROLLBACK"
    StrCpy $InstallerErrorSymbol "TRANSACTION_STATE_UNKNOWN"
    StrCpy $InstallerErrorTarget "$(InstallerComponentInstallationState)"
    StrCpy $InstallerErrorCommand "Sidey.InstallTransaction.exe --action Rollback"
    StrCpy $InstallerErrorMessage "$(TransactionStateUnknown)"
    Call ShowLifecycleError
    SetErrorLevel 1
    Abort

  install_complete:
SectionEnd

Function .onInstFailed
  Call RollbackInstallTransaction
  ${If} $0 != 0
    StrCpy $1 $0
    Call ResetInstallerError
    StrCpy $0 $1
    StrCpy $InstallerErrorNativeCode $1
    StrCpy $InstallerErrorExitCode $1
    StrCpy $InstallerErrorSource "TRANSACTION"
    StrCpy $InstallerErrorStage "ROLLBACK"
    StrCpy $InstallerErrorSymbol "TRANSACTION_STATE_UNKNOWN"
    StrCpy $InstallerErrorTarget "$(InstallerComponentInstallationState)"
    StrCpy $InstallerErrorCommand "Sidey.InstallTransaction.exe --action Rollback"
    StrCpy $InstallerErrorMessage "$(TransactionStateUnknown)"
    Call ShowLifecycleError
    SetErrorLevel 1
  ${EndIf}
FunctionEnd

Function .onGUIEnd
  Call ReleaseSetupMutex
FunctionEnd

Function un.onInit
  SetRegView 64
  SetShellVarContext all
  !insertmacro AcquireSetupMutex $SetupMutexHandle
  ReadRegStr $0 HKLM "${PRODUCT_REGISTRY_KEY}" "Language"
  ${If} $0 != ""
    StrCpy $LANGUAGE $0
  ${EndIf}
  Call un.InitializeInstallerErrorHandling
  StrCpy $DeleteLocalData 0
  StrCpy $DeleteCredentials 0
FunctionEnd

Function un.onGUIEnd
  ${If} $SetupMutexHandle != 0
    System::Call 'kernel32::CloseHandle(p $SetupMutexHandle)'
  ${EndIf}
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
  ClearErrors
  ExecWait '"$INSTDIR\Runtime\SIDEY.UninstallHelper.exe" --stop-sidey-processes' $0
  ${If} ${Errors}
    StrCpy $0 5
  ${EndIf}
  ${If} $0 != 0
    StrCpy $1 $0
    Call un.ResetInstallerError
    StrCpy $0 $1
    StrCpy $InstallerErrorSource "PROCESS"
    StrCpy $InstallerErrorStage "PREFLIGHT"
    StrCpy $InstallerErrorTarget "$(InstallerComponentRemoval)"
    StrCpy $InstallerErrorCommand "SIDEY.UninstallHelper.exe --stop-sidey-processes"
    Goto uninstall_preflight_failed
  ${EndIf}

  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  ClearErrors
  File /oname=$PLUGINSDIR\Sidey.InstallTransaction.exe "${INSTALL_TRANSACTION_EXE}"
  ${If} ${Errors}
    StrCpy $0 5
    StrCpy $1 $0
    Call un.ResetInstallerError
    StrCpy $0 $1
    StrCpy $InstallerErrorSource "FILESYSTEM"
    StrCpy $InstallerErrorStage "PREFLIGHT"
    StrCpy $InstallerErrorTarget "$(InstallerComponentRemoval)"
    StrCpy $InstallerErrorCommand "Extract Sidey.InstallTransaction.exe"
    Goto uninstall_preflight_failed
  ${EndIf}
  System::Call 'kernel32::GetCurrentProcessId() i.r0'
  StrCpy $StagingDirectory "$INSTDIR.sidey-staging-$0"
  StrCpy $RollbackDirectory "$INSTDIR.sidey-rollback"
  ClearErrors
  ExecWait '"$PLUGINSDIR\Sidey.InstallTransaction.exe" --action CleanupForUninstall --install-directory "$INSTDIR" --staging-directory "$StagingDirectory" --rollback-directory "$RollbackDirectory" --version "${APP_VERSION}"' $0
  ${If} ${Errors}
    StrCpy $0 5
  ${EndIf}
  ${If} $0 != 0
    Goto uninstall_state_unknown
  ${EndIf}

  StrCpy $CleanupFailureDetails ""
  ${If} $DeleteLocalData == ${BST_CHECKED}
    ClearErrors
    ExecWait '"$INSTDIR\Runtime\SIDEY.UninstallHelper.exe" --cleanup-local-data-as-desktop-user' $0
    ${If} ${Errors}
      StrCpy $0 5
    ${EndIf}
    ${If} $0 != 0
      StrCpy $CleanupFailureDetails "$(CleanupLocalDataFailure)"
    ${EndIf}
  ${EndIf}
  ${If} $DeleteCredentials == ${BST_CHECKED}
    ClearErrors
    ExecWait '"$INSTDIR\Runtime\SIDEY.UninstallHelper.exe" --cleanup-credentials-as-desktop-user' $0
    ${If} ${Errors}
      StrCpy $0 5
    ${EndIf}
    ${If} $0 != 0
      ${If} $CleanupFailureDetails == ""
        StrCpy $CleanupFailureDetails "$(CleanupCredentialsFailure)"
      ${Else}
        StrCpy $CleanupFailureDetails "$CleanupFailureDetails$\r$\n$(CleanupCredentialsFailure)"
      ${EndIf}
    ${EndIf}
  ${EndIf}

  ; HKCU, LocalAppData and Credential Manager must resolve through the desktop
  ; user's token, including over-the-shoulder UAC with another admin account.
  ClearErrors
  ExecWait '"$INSTDIR\Runtime\SIDEY.UninstallHelper.exe" --cleanup-startup-as-desktop-user' $0
  ${If} ${Errors}
    StrCpy $0 5
  ${EndIf}
  ${If} $0 != 0
    ${If} $CleanupFailureDetails == ""
      StrCpy $CleanupFailureDetails "$(CleanupStartupFailure)"
    ${Else}
      StrCpy $CleanupFailureDetails "$CleanupFailureDetails$\r$\n$(CleanupStartupFailure)"
    ${EndIf}
  ${EndIf}
  ${If} $CleanupFailureDetails != ""
    Call un.ResetInstallerError
    StrCpy $InstallerErrorStatus "COMPLETED_WITH_WARNINGS"
    StrCpy $InstallerErrorCategory "CLEANUP_PARTIAL"
    StrCpy $InstallerErrorSource "UNINSTALL_HELPER"
    StrCpy $InstallerErrorNativeCode "MULTIPLE"
    StrCpy $InstallerErrorStage "CLEANUP"
    StrCpy $InstallerErrorSymbol "OPTIONAL_CLEANUP_FAILED"
    StrCpy $InstallerErrorDetail $CleanupFailureDetails
    StrCpy $InstallerErrorTarget "$(InstallerComponentCurrentUserData)"
    StrCpy $InstallerErrorCommand "SIDEY.UninstallHelper.exe"
    StrCpy $InstallerErrorMessage "$(CleanupFailed)"
    Call un.ShowLifecycleError
  ${EndIf}
  Delete "$SMPROGRAMS\SIDEY\SIDEY.lnk"
  Delete "$SMPROGRAMS\SIDEY\Uninstall SIDEY.lnk"
  RMDir "$SMPROGRAMS\SIDEY"
  Delete "$INSTDIR\Runtime\SIDEY.UninstallHelper.exe"
  !include "${PAYLOAD_UNINSTALL_INCLUDE}"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR\Runtime"
  RMDir "$INSTDIR"
  DeleteRegKey HKLM "${PRODUCT_UNINSTALL_KEY}"
  DeleteRegKey HKLM "${PRODUCT_PROTOCOL_KEY}"
  DeleteRegKey HKLM "${PRODUCT_REGISTRY_KEY}"
  Goto uninstall_complete

  uninstall_preflight_failed:
    StrCpy $1 $0
    StrCpy $0 $1
    StrCpy $InstallerErrorStatus "FAILED"
    StrCpy $InstallerErrorCategory "UNKNOWN_ERROR"
    StrCpy $InstallerErrorResultLoaded "false"
    StrCpy $InstallerErrorNativeCode $1
    StrCpy $InstallerErrorExitCode $1
    StrCpy $InstallerErrorSymbol "UNINSTALL_PREFLIGHT_FAILED"
    StrCpy $InstallerErrorMessage "$(UninstallPreflightFailed)"
    Call un.ShowLifecycleError
    SetErrorLevel 1
    Abort

  uninstall_state_unknown:
    StrCpy $1 $0
    Call un.ResetInstallerError
    StrCpy $0 $1
    StrCpy $InstallerErrorNativeCode $1
    StrCpy $InstallerErrorExitCode $1
    StrCpy $InstallerErrorSource "TRANSACTION"
    StrCpy $InstallerErrorStage "CLEANUP"
    StrCpy $InstallerErrorSymbol "UNINSTALL_STATE_UNKNOWN"
    StrCpy $InstallerErrorTarget "$(InstallerComponentRemovalState)"
    StrCpy $InstallerErrorCommand "Sidey.InstallTransaction.exe --action CleanupForUninstall"
    StrCpy $InstallerErrorMessage "$(UninstallStateUnknown)"
    Call un.ShowLifecycleError
    SetErrorLevel 1
    Abort

  uninstall_complete:
SectionEnd
