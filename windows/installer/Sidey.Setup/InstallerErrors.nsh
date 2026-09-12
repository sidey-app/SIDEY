; Category-based installer UI. Native codes are normalized by InstallerErrors.ps1;
; this file deliberately branches only on application-owned categories/statuses.

Var InstallerErrorStatus
Var InstallerErrorCategory
Var InstallerErrorSource
Var InstallerErrorNativeCode
Var InstallerErrorStage
Var InstallerErrorSymbol
Var InstallerErrorDetail
Var InstallerErrorTarget
Var InstallerErrorCommand
Var InstallerErrorExitCode
Var InstallerErrorMessage
Var InstallerErrorResultPath
Var InstallerErrorLogPath
Var InstallerErrorResultLoaded

LangString InstallerErrorNetwork ${LANG_ENGLISH} "SIDEY cannot be installed.$\r$\n$\r$\nThe connection to the download server was interrupted. Check your internet connection and try again.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorDownload ${LANG_ENGLISH} "SIDEY cannot be installed.$\r$\n$\r$\nA required component could not be downloaded. Check your connection and try again.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorDiskFull ${LANG_ENGLISH} "SIDEY cannot be installed.$\r$\n$\r$\nThere is not enough storage space. Free space on the installation drive and try again.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorPermission ${LANG_ENGLISH} "SIDEY cannot be installed.$\r$\n$\r$\nWindows did not allow the required change. Sign in with an administrator account and run Setup again.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorPolicy ${LANG_ENGLISH} "SIDEY cannot be installed.$\r$\n$\r$\nThe current Windows app installation policy does not allow this installation. If this PC is managed by a company or school, contact your system administrator.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorPackage ${LANG_ENGLISH} "SIDEY cannot be installed.$\r$\n$\r$\nA required installation package could not be opened or is damaged. Download Setup again and retry.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorSignature ${LANG_ENGLISH} "SIDEY cannot be installed.$\r$\n$\r$\nWindows could not verify a required component. Update Windows, download Setup again, and retry.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorDependency ${LANG_ENGLISH} "SIDEY cannot be installed.$\r$\n$\r$\nA component required by the program is unavailable. Update Windows and run Setup again.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorDependencyConflict ${LANG_ENGLISH} "SIDEY cannot be installed.$\r$\n$\r$\nA required component is missing or conflicts with an installed package. Update Windows and try again.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorIncompatible ${LANG_ENGLISH} "SIDEY cannot be installed.$\r$\n$\r$\nThis package is not compatible with this version or architecture of Windows. Check the SIDEY system requirements.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorAppInUse ${LANG_ENGLISH} "SIDEY cannot be installed.$\r$\n$\r$\nA program or component that must be updated is currently in use. Close SIDEY and related programs, then try again.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorAnotherInstall ${LANG_ENGLISH} "SIDEY cannot be installed.$\r$\n$\r$\nAnother program is being installed. Complete that installation, then try again.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorAlreadyInstalled ${LANG_ENGLISH} "SIDEY cannot be installed.$\r$\n$\r$\nThe same or a newer version of this component is already installed. Remove the conflicting version or use a newer Setup.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorRestart ${LANG_ENGLISH} "Windows must be restarted.$\r$\n$\r$\nThe required component was installed, but a restart is needed to finish. Restart Windows, then run Setup again.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorCancelled ${LANG_ENGLISH} "Installation was cancelled.$\r$\n$\r$\nNo further changes were made. Run Setup again when you are ready.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorRegistration ${LANG_ENGLISH} "SIDEY cannot be installed.$\r$\n$\r$\nWindows could not register a required component. Restart Windows and try again.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorRepository ${LANG_ENGLISH} "SIDEY cannot be installed.$\r$\n$\r$\nThe Windows app package database is damaged. Run Windows Update; if the problem continues, contact your system administrator.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"
LangString InstallerErrorUnknown ${LANG_ENGLISH} "A problem occurred during installation.$\r$\n$\r$\nTry again. If the problem continues, provide the error code below to customer support.$\r$\n$\r$\nError code: $InstallerErrorNativeCode"

LangString InstallerErrorNetwork ${LANG_KOREAN} "SIDEY를 설치할 수 없습니다.$\r$\n$\r$\n다운로드 서버와의 연결이 중단되었습니다. 인터넷 연결을 확인한 뒤 다시 시도하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorDownload ${LANG_KOREAN} "SIDEY를 설치할 수 없습니다.$\r$\n$\r$\n필수 구성 요소를 다운로드하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorDiskFull ${LANG_KOREAN} "SIDEY를 설치할 수 없습니다.$\r$\n$\r$\n저장 공간이 부족합니다. 프로그램을 설치할 디스크의 여유 공간을 확보한 뒤 다시 시도하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorPermission ${LANG_KOREAN} "SIDEY를 설치할 수 없습니다.$\r$\n$\r$\nWindows에서 필요한 변경을 허용하지 않았습니다. 관리자 계정으로 로그인한 뒤 설치 프로그램을 다시 실행하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorPolicy ${LANG_KOREAN} "SIDEY를 설치할 수 없습니다.$\r$\n$\r$\n현재 Windows의 앱 설치 정책에서 이 설치를 허용하지 않습니다. 회사나 학교에서 관리하는 PC라면 시스템 관리자에게 문의하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorPackage ${LANG_KOREAN} "SIDEY를 설치할 수 없습니다.$\r$\n$\r$\n필수 설치 패키지를 열 수 없거나 패키지가 손상되었습니다. 설치 프로그램을 다시 다운로드한 뒤 시도하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorSignature ${LANG_KOREAN} "SIDEY를 설치할 수 없습니다.$\r$\n$\r$\nWindows에서 필수 구성 요소를 확인할 수 없습니다. Windows를 업데이트하고 설치 프로그램을 다시 다운로드한 뒤 시도하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorDependency ${LANG_KOREAN} "SIDEY를 설치할 수 없습니다.$\r$\n$\r$\n프로그램에 필요한 구성 요소를 사용할 수 없습니다. Windows를 업데이트한 뒤 설치 프로그램을 다시 실행하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorDependencyConflict ${LANG_KOREAN} "SIDEY를 설치할 수 없습니다.$\r$\n$\r$\n필수 구성 요소가 없거나 설치된 패키지와 충돌합니다. Windows를 업데이트한 뒤 다시 시도하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorIncompatible ${LANG_KOREAN} "SIDEY를 설치할 수 없습니다.$\r$\n$\r$\n이 패키지는 현재 Windows 버전 또는 시스템 종류와 호환되지 않습니다. SIDEY 시스템 요구 사항을 확인하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorAppInUse ${LANG_KOREAN} "SIDEY를 설치할 수 없습니다.$\r$\n$\r$\n업데이트해야 할 프로그램이나 구성 요소를 사용 중입니다. SIDEY와 관련 프로그램을 종료한 뒤 다시 시도하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorAnotherInstall ${LANG_KOREAN} "SIDEY를 설치할 수 없습니다.$\r$\n$\r$\n다른 프로그램을 설치하고 있습니다. 진행 중인 설치를 완료한 뒤 다시 시도하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorAlreadyInstalled ${LANG_KOREAN} "SIDEY를 설치할 수 없습니다.$\r$\n$\r$\n같거나 더 새로운 버전의 구성 요소가 이미 설치되어 있습니다. 충돌하는 버전을 제거하거나 더 최신 설치 프로그램을 사용하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorRestart ${LANG_KOREAN} "Windows를 다시 시작해야 합니다.$\r$\n$\r$\n필수 구성 요소는 설치되었지만 완료하려면 다시 시작해야 합니다. Windows를 다시 시작한 뒤 설치 프로그램을 다시 실행하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorCancelled ${LANG_KOREAN} "설치가 취소되었습니다.$\r$\n$\r$\n더 이상 변경하지 않았습니다. 준비가 되면 설치 프로그램을 다시 실행하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorRegistration ${LANG_KOREAN} "SIDEY를 설치할 수 없습니다.$\r$\n$\r$\nWindows에서 필수 구성 요소를 등록하지 못했습니다. Windows를 다시 시작한 뒤 다시 시도하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorRepository ${LANG_KOREAN} "SIDEY를 설치할 수 없습니다.$\r$\n$\r$\nWindows 앱 패키지 데이터베이스가 손상되었습니다. Windows 업데이트를 실행하고, 문제가 계속되면 시스템 관리자에게 문의하세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"
LangString InstallerErrorUnknown ${LANG_KOREAN} "설치 중 문제가 발생했습니다.$\r$\n$\r$\n다시 시도해도 문제가 계속되면 아래 오류 코드를 고객지원에 알려주세요.$\r$\n$\r$\n오류 코드: $InstallerErrorNativeCode"

; The five additional installer languages retain the same category/action split.
LangString InstallerErrorNetwork ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\nダウンロードサーバーとの接続が切断されました。インターネット接続を確認して、もう一度お試しください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorDownload ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n必要なコンポーネントをダウンロードできませんでした。接続を確認して、もう一度お試しください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorDiskFull ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n空き容量が不足しています。インストール先ドライブの空き容量を増やして、もう一度お試しください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorPermission ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\nWindows が必要な変更を許可しませんでした。管理者アカウントでサインインして、セットアップを再実行してください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorPolicy ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n現在の Windows アプリインストールポリシーでは、このインストールは許可されていません。会社や学校が管理する PC の場合は、システム管理者にお問い合わせください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorPackage ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n必要なインストールパッケージを開けないか、破損しています。セットアップを再度ダウンロードしてください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorSignature ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n必要なコンポーネントを確認できませんでした。Windows を更新し、セットアップを再度ダウンロードしてください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorDependency ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\nプログラムに必要なコンポーネントを利用できません。Windows を更新して、セットアップを再実行してください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorDependencyConflict ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n必要なコンポーネントがないか、インストール済みパッケージと競合しています。Windows を更新して、もう一度お試しください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorIncompatible ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\nこのパッケージは現在の Windows バージョンまたはシステムの種類に対応していません。システム要件をご確認ください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorAppInUse ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n更新が必要なプログラムまたはコンポーネントが使用中です。SIDEY と関連プログラムを終了して、もう一度お試しください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorAnotherInstall ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n別のプログラムをインストールしています。そのインストールを完了してから、もう一度お試しください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorAlreadyInstalled ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n同じか新しいバージョンのコンポーネントが既にインストールされています。競合するバージョンを削除するか、新しいセットアップを使用してください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorRestart ${LANG_JAPANESE} "Windows の再起動が必要です。$\r$\n$\r$\n必要なコンポーネントはインストールされましたが、完了するには再起動が必要です。再起動後にセットアップを再実行してください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorCancelled ${LANG_JAPANESE} "インストールはキャンセルされました。$\r$\n$\r$\nこれ以上の変更は行われていません。準備ができたらセットアップを再実行してください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorRegistration ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\nWindows が必要なコンポーネントを登録できませんでした。Windows を再起動して、もう一度お試しください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorRepository ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\nWindows のアプリパッケージデータベースが破損しています。Windows Update を実行し、解決しない場合はシステム管理者にお問い合わせください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"
LangString InstallerErrorUnknown ${LANG_JAPANESE} "インストール中に問題が発生しました。$\r$\n$\r$\nもう一度試しても問題が続く場合は、次のエラーコードをカスタマーサポートにお知らせください。$\r$\n$\r$\nエラーコード: $InstallerErrorNativeCode"

LangString InstallerErrorNetwork ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n与下载服务器的连接已中断。请检查网络连接后重试。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorDownload ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n无法下载所需组件。请检查网络连接后重试。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorDiskFull ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n存储空间不足。请释放安装驱动器的空间后重试。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorPermission ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\nWindows 不允许进行所需更改。请使用管理员账户登录并重新运行安装程序。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorPolicy ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n当前 Windows 应用安装策略不允许此次安装。如果此电脑由公司或学校管理，请联系系统管理员。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorPackage ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n无法打开所需安装包，或安装包已损坏。请重新下载安装程序后重试。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorSignature ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\nWindows 无法验证所需组件。请更新 Windows，重新下载安装程序后重试。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorDependency ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n程序所需组件不可用。请更新 Windows 后重新运行安装程序。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorDependencyConflict ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n缺少所需组件，或该组件与已安装的软件包冲突。请更新 Windows 后重试。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorIncompatible ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n此安装包与当前 Windows 版本或系统类型不兼容。请检查 SIDEY 系统要求。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorAppInUse ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n需要更新的程序或组件正在使用中。请关闭 SIDEY 和相关程序后重试。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorAnotherInstall ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n正在安装另一个程序。请等待该安装完成后重试。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorAlreadyInstalled ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n已安装相同或更新版本的组件。请删除冲突版本或使用更新的安装程序。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorRestart ${LANG_SIMPCHINESE} "需要重新启动 Windows。$\r$\n$\r$\n所需组件已安装，但需要重启才能完成。请重启 Windows 后重新运行安装程序。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorCancelled ${LANG_SIMPCHINESE} "安装已取消。$\r$\n$\r$\n未进行其他更改。准备好后请重新运行安装程序。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorRegistration ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\nWindows 无法注册所需组件。请重启 Windows 后重试。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorRepository ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\nWindows 应用包数据库已损坏。请运行 Windows 更新；如果问题仍然存在，请联系系统管理员。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"
LangString InstallerErrorUnknown ${LANG_SIMPCHINESE} "安装过程中出现问题。$\r$\n$\r$\n请重试。如果问题仍然存在，请将以下错误代码提供给客户支持。$\r$\n$\r$\n错误代码: $InstallerErrorNativeCode"

LangString InstallerErrorNetwork ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n與下載伺服器的連線已中斷。請檢查網路連線後再試一次。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorDownload ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n無法下載必要元件。請檢查網路連線後再試一次。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorDiskFull ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n儲存空間不足。請釋放安裝磁碟機的空間後再試一次。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorPermission ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\nWindows 不允許進行必要變更。請使用系統管理員帳戶登入並重新執行安裝程式。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorPolicy ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n目前的 Windows 應用程式安裝原則不允許此次安裝。如果此電腦由公司或學校管理，請聯絡系統管理員。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorPackage ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n無法開啟必要的安裝套件，或套件已損毀。請重新下載安裝程式後再試一次。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorSignature ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\nWindows 無法驗證必要元件。請更新 Windows，重新下載安裝程式後再試一次。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorDependency ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n程式所需的元件無法使用。請更新 Windows 後重新執行安裝程式。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorDependencyConflict ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n缺少必要元件，或該元件與已安裝的套件衝突。請更新 Windows 後再試一次。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorIncompatible ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n此套件與目前的 Windows 版本或系統類型不相容。請查看 SIDEY 系統需求。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorAppInUse ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n需要更新的程式或元件正在使用中。請關閉 SIDEY 與相關程式後再試一次。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorAnotherInstall ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n正在安裝另一個程式。請先完成該安裝，再試一次。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorAlreadyInstalled ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n已安裝相同或較新版本的元件。請移除衝突版本或使用較新的安裝程式。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorRestart ${LANG_TRADCHINESE} "必須重新啟動 Windows。$\r$\n$\r$\n必要元件已安裝，但必須重新啟動才能完成。請重新啟動 Windows，再執行安裝程式。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorCancelled ${LANG_TRADCHINESE} "安裝已取消。$\r$\n$\r$\n未進行其他變更。準備好後請重新執行安裝程式。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorRegistration ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\nWindows 無法註冊必要元件。請重新啟動 Windows 後再試一次。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorRepository ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\nWindows 應用程式套件資料庫已損毀。請執行 Windows Update；若問題持續，請聯絡系統管理員。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"
LangString InstallerErrorUnknown ${LANG_TRADCHINESE} "安裝期間發生問題。$\r$\n$\r$\n請再試一次。若問題持續，請將以下錯誤代碼提供給客戶支援。$\r$\n$\r$\n錯誤代碼: $InstallerErrorNativeCode"

LangString InstallerErrorNetwork ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nСоединение с сервером загрузки было прервано. Проверьте подключение к Интернету и повторите попытку.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorDownload ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nНе удалось загрузить необходимый компонент. Проверьте подключение и повторите попытку.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorDiskFull ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nНедостаточно места на диске. Освободите место на диске установки и повторите попытку.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorPermission ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nWindows не разрешила необходимое изменение. Войдите с учетной записью администратора и снова запустите установку.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorPolicy ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nТекущая политика установки приложений Windows запрещает эту установку. Если компьютер управляется организацией, обратитесь к системному администратору.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorPackage ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nНе удалось открыть необходимый пакет установки, либо он поврежден. Скачайте установщик заново и повторите попытку.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorSignature ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nWindows не удалось проверить необходимый компонент. Обновите Windows, скачайте установщик заново и повторите попытку.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorDependency ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nНеобходимый компонент недоступен. Обновите Windows и снова запустите установку.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorDependencyConflict ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nНеобходимый компонент отсутствует или конфликтует с установленным пакетом. Обновите Windows и повторите попытку.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorIncompatible ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nПакет несовместим с этой версией или архитектурой Windows. Проверьте системные требования SIDEY.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorAppInUse ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nОбновляемая программа или компонент сейчас используется. Закройте SIDEY и связанные программы, затем повторите попытку.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorAnotherInstall ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nВыполняется установка другой программы. Дождитесь ее завершения и повторите попытку.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorAlreadyInstalled ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nТа же или более новая версия компонента уже установлена. Удалите конфликтующую версию или используйте более новый установщик.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorRestart ${LANG_RUSSIAN} "Необходимо перезапустить Windows.$\r$\n$\r$\nКомпонент установлен, но для завершения требуется перезапуск. Перезапустите Windows и снова запустите установку.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorCancelled ${LANG_RUSSIAN} "Установка отменена.$\r$\n$\r$\nДругие изменения не выполнялись. Запустите установщик снова, когда будете готовы.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorRegistration ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nWindows не удалось зарегистрировать необходимый компонент. Перезапустите Windows и повторите попытку.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorRepository ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nБаза данных пакетов приложений Windows повреждена. Запустите Центр обновления Windows; если проблема останется, обратитесь к администратору.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"
LangString InstallerErrorUnknown ${LANG_RUSSIAN} "Во время установки возникла проблема.$\r$\n$\r$\nПовторите попытку. Если проблема сохранится, сообщите службе поддержки указанный ниже код ошибки.$\r$\n$\r$\nКод ошибки: $InstallerErrorNativeCode"

LangString InstallerErrorNetwork ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nЗ’єднання із сервером завантаження перервано. Перевірте підключення до Інтернету та повторіть спробу.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorDownload ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nНе вдалося завантажити потрібний компонент. Перевірте підключення та повторіть спробу.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorDiskFull ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nНедостатньо місця на диску. Звільніть місце на диску встановлення та повторіть спробу.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorPermission ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nWindows не дозволила потрібну зміну. Увійдіть з обліковим записом адміністратора та знову запустіть інсталятор.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorPolicy ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nПоточна політика інсталяції програм Windows не дозволяє це встановлення. Якщо ПК керується організацією, зверніться до системного адміністратора.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorPackage ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nНе вдалося відкрити потрібний пакет інсталяції, або його пошкоджено. Завантажте інсталятор знову та повторіть спробу.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorSignature ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nWindows не вдалося перевірити потрібний компонент. Оновіть Windows, завантажте інсталятор знову та повторіть спробу.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorDependency ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nПотрібний компонент недоступний. Оновіть Windows і знову запустіть інсталятор.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorDependencyConflict ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nПотрібний компонент відсутній або конфліктує з установленим пакетом. Оновіть Windows і повторіть спробу.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorIncompatible ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nПакет несумісний із цією версією або архітектурою Windows. Перевірте системні вимоги SIDEY.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorAppInUse ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nПрограма або компонент, який треба оновити, зараз використовується. Закрийте SIDEY і пов’язані програми та повторіть спробу.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorAnotherInstall ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nВиконується встановлення іншої програми. Завершіть його та повторіть спробу.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorAlreadyInstalled ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nТака сама або новіша версія компонента вже встановлена. Видаліть конфліктну версію або скористайтеся новішим інсталятором.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorRestart ${LANG_UKRAINIAN} "Потрібно перезапустити Windows.$\r$\n$\r$\nПотрібний компонент установлено, але для завершення потрібен перезапуск. Перезапустіть Windows і знову запустіть інсталятор.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorCancelled ${LANG_UKRAINIAN} "Встановлення скасовано.$\r$\n$\r$\nІнших змін не внесено. Запустіть інсталятор знову, коли будете готові.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorRegistration ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nWindows не вдалося зареєструвати потрібний компонент. Перезапустіть Windows і повторіть спробу.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorRepository ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nБазу даних пакетів програм Windows пошкоджено. Запустіть Windows Update; якщо проблема не зникне, зверніться до адміністратора.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"
LangString InstallerErrorUnknown ${LANG_UKRAINIAN} "Під час встановлення виникла проблема.$\r$\n$\r$\nПовторіть спробу. Якщо проблема не зникне, повідомте службі підтримки наведений нижче код помилки.$\r$\n$\r$\nКод помилки: $InstallerErrorNativeCode"

Function InitializeInstallerErrorHandling
  InitPluginsDir
  ; Sidey.Setup.nsi uses SetShellVarContext all, so $APPDATA resolves to
  ; the machine-wide ProgramData folder even during over-the-shoulder elevation.
  CreateDirectory "$APPDATA\SIDEY\Installer\Logs"
  ${GetTime} "" "L" $0 $1 $2 $3 $4 $5 $6
  StrCpy $InstallerErrorLogPath "$APPDATA\SIDEY\Installer\Logs\SIDEY-Setup-$2$1$0-$4$5$6.log"
  StrCpy $InstallerErrorResultPath "$PLUGINSDIR\InstallerResult.ini"
FunctionEnd

Function ResetInstallerError
  StrCpy $InstallerErrorStatus "FAILED"
  StrCpy $InstallerErrorCategory "UNKNOWN_ERROR"
  StrCpy $InstallerErrorSource "UNKNOWN"
  StrCpy $InstallerErrorNativeCode "UNKNOWN"
  StrCpy $InstallerErrorStage "INSTALL"
  StrCpy $InstallerErrorSymbol ""
  StrCpy $InstallerErrorDetail ""
  StrCpy $InstallerErrorTarget ""
  StrCpy $InstallerErrorCommand ""
  StrCpy $InstallerErrorExitCode ""
  StrCpy $InstallerErrorResultLoaded "false"
  Delete "$InstallerErrorResultPath"
FunctionEnd

Function LoadInstallerResult
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "status"
  ${If} $R0 != ""
    StrCpy $InstallerErrorStatus $R0
    StrCpy $InstallerErrorResultLoaded "true"
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "category"
  ${If} $R0 != ""
    StrCpy $InstallerErrorCategory $R0
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "source"
  ${If} $R0 != ""
    StrCpy $InstallerErrorSource $R0
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "nativeCode"
  ${If} $R0 != ""
    StrCpy $InstallerErrorNativeCode $R0
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "stage"
  ${If} $R0 != ""
    StrCpy $InstallerErrorStage $R0
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "symbol"
  ${If} $R0 != ""
    StrCpy $InstallerErrorSymbol $R0
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "detail"
  ${If} $R0 != ""
    StrCpy $InstallerErrorDetail $R0
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "target"
  ${If} $R0 != ""
    StrCpy $InstallerErrorTarget $R0
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "command"
  ${If} $R0 != ""
    StrCpy $InstallerErrorCommand $R0
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "exitCode"
  ${If} $R0 != ""
    StrCpy $InstallerErrorExitCode $R0
  ${EndIf}
FunctionEnd

Function NormalizeInstallerError
  Delete "$InstallerErrorResultPath"
  ${DisableX64FSRedirection}
  nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\SetupRuntime.ps1" -NativeCode "$InstallerErrorNativeCode" -Source "$InstallerErrorSource" -Stage "$InstallerErrorStage" -Target "$InstallerErrorTarget" -CommandDescription "$InstallerErrorCommand" -ExitCode "$InstallerErrorExitCode" -ResultPath "$InstallerErrorResultPath" -LogPath "$InstallerErrorLogPath" -InstallerVersion "${APP_VERSION}"'
  Pop $R0
  ${EnableX64FSRedirection}
  Call LoadInstallerResult
FunctionEnd

Function GetInstallerErrorMessage
  ${If} $InstallerErrorCategory == "NETWORK_ERROR"
    StrCpy $InstallerErrorMessage "$(InstallerErrorNetwork)"
  ${ElseIf} $InstallerErrorCategory == "DOWNLOAD_FAILED"
    StrCpy $InstallerErrorMessage "$(InstallerErrorDownload)"
  ${ElseIf} $InstallerErrorCategory == "DISK_FULL"
    StrCpy $InstallerErrorMessage "$(InstallerErrorDiskFull)"
  ${ElseIf} $InstallerErrorCategory == "PERMISSION_DENIED"
    StrCpy $InstallerErrorMessage "$(InstallerErrorPermission)"
  ${ElseIf} $InstallerErrorCategory == "BLOCKED_BY_POLICY"
    StrCpy $InstallerErrorMessage "$(InstallerErrorPolicy)"
  ${ElseIf} $InstallerErrorCategory == "PACKAGE_CORRUPTED"
    StrCpy $InstallerErrorMessage "$(InstallerErrorPackage)"
  ${ElseIf} $InstallerErrorCategory == "SIGNATURE_ERROR"
    StrCpy $InstallerErrorMessage "$(InstallerErrorSignature)"
  ${ElseIf} $InstallerErrorCategory == "DEPENDENCY_MISSING"
    StrCpy $InstallerErrorMessage "$(InstallerErrorDependency)"
  ${ElseIf} $InstallerErrorCategory == "DEPENDENCY_CONFLICT"
    StrCpy $InstallerErrorMessage "$(InstallerErrorDependencyConflict)"
  ${ElseIf} $InstallerErrorCategory == "INCOMPATIBLE_SYSTEM"
    StrCpy $InstallerErrorMessage "$(InstallerErrorIncompatible)"
  ${ElseIf} $InstallerErrorCategory == "APP_IN_USE"
    StrCpy $InstallerErrorMessage "$(InstallerErrorAppInUse)"
  ${ElseIf} $InstallerErrorCategory == "ANOTHER_INSTALLATION_RUNNING"
    StrCpy $InstallerErrorMessage "$(InstallerErrorAnotherInstall)"
  ${ElseIf} $InstallerErrorCategory == "ALREADY_INSTALLED"
    StrCpy $InstallerErrorMessage "$(InstallerErrorAlreadyInstalled)"
  ${ElseIf} $InstallerErrorCategory == "REBOOT_REQUIRED"
    StrCpy $InstallerErrorMessage "$(InstallerErrorRestart)"
  ${ElseIf} $InstallerErrorCategory == "USER_CANCELLED"
    StrCpy $InstallerErrorMessage "$(InstallerErrorCancelled)"
  ${ElseIf} $InstallerErrorCategory == "PACKAGE_REGISTRATION_FAILED"
    StrCpy $InstallerErrorMessage "$(InstallerErrorRegistration)"
  ${ElseIf} $InstallerErrorCategory == "PACKAGE_REPOSITORY_CORRUPTED"
    StrCpy $InstallerErrorMessage "$(InstallerErrorRepository)"
  ${Else}
    StrCpy $InstallerErrorMessage "$(InstallerErrorUnknown)"
  ${EndIf}
FunctionEnd

Function LogInstallerErrorFallback
  FileOpen $R0 "$InstallerErrorLogPath" a
  ${IfNot} ${Errors}
    ${GetTime} "" "L" $R1 $R2 $R3 $R4 $R5 $R6 $R7
    FileWrite $R0 "[InstallerError]$\r$\n"
    FileWrite $R0 "timestamp=$R3-$R2-$R1T$R5:$R6:$R7$\r$\n"
    FileWrite $R0 "status=$InstallerErrorStatus$\r$\n"
    FileWrite $R0 "category=$InstallerErrorCategory$\r$\n"
    FileWrite $R0 "source=$InstallerErrorSource$\r$\n"
    FileWrite $R0 "nativeCode=$InstallerErrorNativeCode$\r$\n"
    FileWrite $R0 "stage=$InstallerErrorStage$\r$\n"
    FileWrite $R0 "message=$InstallerErrorSymbol$\r$\n"
    FileWrite $R0 "target=$InstallerErrorTarget$\r$\n"
    FileWrite $R0 "command=$InstallerErrorCommand$\r$\n"
    FileWrite $R0 "exitCode=$InstallerErrorExitCode$\r$\n"
    FileWrite $R0 "installerVersion=${APP_VERSION}$\r$\n$\r$\n"
    FileClose $R0
  ${EndIf}
FunctionEnd

Function ShowInstallerError
  ${If} $InstallerErrorResultLoaded != "true"
    Call LogInstallerErrorFallback
  ${EndIf}
  Call GetInstallerErrorMessage
  DetailPrint "Installer result: status=$InstallerErrorStatus category=$InstallerErrorCategory source=$InstallerErrorSource nativeCode=$InstallerErrorNativeCode stage=$InstallerErrorStage"
  ${If} $InstallerErrorStatus == "SUCCESS_REBOOT_REQUIRED"
    MessageBox MB_OK|MB_ICONEXCLAMATION "$InstallerErrorMessage" /SD IDOK
  ${Else}
    MessageBox MB_OK|MB_ICONSTOP "$InstallerErrorMessage" /SD IDOK
  ${EndIf}
FunctionEnd
