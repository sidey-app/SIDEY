# Windows PowerShell 5.1-compatible installer error normalization and reporting.
$script:SideyInstallerCategories = @(
    'NETWORK_ERROR', 'DOWNLOAD_FAILED', 'DISK_FULL', 'PERMISSION_DENIED',
    'BLOCKED_BY_POLICY', 'PACKAGE_CORRUPTED', 'SIGNATURE_ERROR',
    'DEPENDENCY_MISSING', 'DEPENDENCY_CONFLICT', 'INCOMPATIBLE_SYSTEM',
    'APP_IN_USE', 'ANOTHER_INSTALLATION_RUNNING', 'ALREADY_INSTALLED',
    'REBOOT_REQUIRED', 'USER_CANCELLED', 'PACKAGE_REGISTRATION_FAILED',
    'PACKAGE_REPOSITORY_CORRUPTED', 'UNKNOWN_ERROR'
)

$script:SideyInstallerErrorDefinitions = @{
    '0x80073CF0' = @('PACKAGE_CORRUPTED', 'ERROR_INSTALL_OPEN_PACKAGE_FAILED')
    '0x80073CF3' = @('DEPENDENCY_CONFLICT', 'ERROR_INSTALL_RESOLVE_DEPENDENCY_FAILED')
    '0x80073CF4' = @('DISK_FULL', 'ERROR_INSTALL_OUT_OF_DISK_SPACE')
    '0x80073CF5' = @('DOWNLOAD_FAILED', 'ERROR_INSTALL_NETWORK_FAILURE')
    '0x80073CF6' = @('PACKAGE_REGISTRATION_FAILED', 'ERROR_INSTALL_REGISTRATION_FAILURE')
    '0x80073CF9' = @('UNKNOWN_ERROR', 'ERROR_INSTALL_FAILED')
    '0x80073CFB' = @('ALREADY_INSTALLED', 'ERROR_PACKAGE_ALREADY_EXISTS')
    '0x80073CFD' = @('DEPENDENCY_MISSING', 'ERROR_INSTALL_PREREQUISITE_FAILED')
    '0x80073CFE' = @('PACKAGE_REPOSITORY_CORRUPTED', 'ERROR_PACKAGE_REPOSITORY_CORRUPTED')
    '0x80073CFF' = @('BLOCKED_BY_POLICY', 'ERROR_INSTALL_POLICY_FAILURE')
    '0x80073D01' = @('BLOCKED_BY_POLICY', 'ERROR_DEPLOYMENT_BLOCKED_BY_POLICY')
    '0x80073D02' = @('APP_IN_USE', 'ERROR_PACKAGES_IN_USE')
    '0x80073D06' = @('ALREADY_INSTALLED', 'ERROR_INSTALL_PACKAGE_DOWNGRADE')
    '0x80073D10' = @('INCOMPATIBLE_SYSTEM', 'ERROR_INSTALL_WRONG_PROCESSOR_ARCHITECTURE')
    '0x80073D28' = @('PERMISSION_DENIED', 'ERROR_PACKAGED_SERVICE_REQUIRES_ADMIN_PRIVILEGES')
    '0x80080203' = @('PACKAGE_CORRUPTED', 'APPX_E_MISSING_REQUIRED_FILE')
    '0x80080206' = @('PACKAGE_CORRUPTED', 'APPX_E_CORRUPT_CONTENT')
    '0x80080207' = @('PACKAGE_CORRUPTED', 'APPX_E_BLOCK_HASH_INVALID')
    '0x800B0100' = @('SIGNATURE_ERROR', 'TRUST_E_NOSIGNATURE')
    '0x800B0109' = @('SIGNATURE_ERROR', 'CERT_E_UNTRUSTEDROOT')
    '0x80070005' = @('PERMISSION_DENIED', 'E_ACCESSDENIED')
    '0x80070070' = @('DISK_FULL', 'ERROR_DISK_FULL')
    '12002'      = @('NETWORK_ERROR', 'ERROR_INTERNET_TIMEOUT')
    '12007'      = @('NETWORK_ERROR', 'ERROR_INTERNET_NAME_NOT_RESOLVED')
    '12029'      = @('NETWORK_ERROR', 'ERROR_INTERNET_CANNOT_CONNECT')
    '12030'      = @('NETWORK_ERROR', 'ERROR_INTERNET_CONNECTION_ABORTED')
    '12031'      = @('NETWORK_ERROR', 'ERROR_INTERNET_CONNECTION_RESET')
    '12163'      = @('NETWORK_ERROR', 'ERROR_INTERNET_DISCONNECTED')
    '1602'       = @('USER_CANCELLED', 'ERROR_INSTALL_USEREXIT')
    '1603'       = @('UNKNOWN_ERROR', 'ERROR_INSTALL_FAILURE')
    '1618'       = @('ANOTHER_INSTALLATION_RUNNING', 'ERROR_INSTALL_ALREADY_RUNNING')
    '1619'       = @('PACKAGE_CORRUPTED', 'ERROR_INSTALL_PACKAGE_OPEN_FAILED')
    '1620'       = @('PACKAGE_CORRUPTED', 'ERROR_INSTALL_PACKAGE_INVALID')
    '1625'       = @('BLOCKED_BY_POLICY', 'ERROR_INSTALL_PACKAGE_REJECTED')
    '1633'       = @('INCOMPATIBLE_SYSTEM', 'ERROR_INSTALL_PLATFORM_UNSUPPORTED')
    '1638'       = @('ALREADY_INSTALLED', 'ERROR_PRODUCT_VERSION')
}

function ConvertTo-SideyNativeCode {
    param($NativeCode)
    if ($null -eq $NativeCode -or [string]::IsNullOrWhiteSpace([string]$NativeCode)) {
        return 'UNKNOWN'
    }

    $text = ([string]$NativeCode).Trim()
    if ($text -match '^0[xX](?<hex>[0-9a-fA-F]{1,8})$') {
        $value = [uint32]::Parse($Matches.hex, [Globalization.NumberStyles]::HexNumber,
            [Globalization.CultureInfo]::InvariantCulture)
        return '0x{0:X8}' -f $value
    }

    $number = 0L
    if (-not [long]::TryParse($text, [Globalization.NumberStyles]::Integer,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        return $text
    }
    if ($number -lt 0 -and $number -ge [int32]::MinValue) {
        $unsigned = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$number), 0)
        return '0x{0:X8}' -f $unsigned
    }
    if ($number -gt [int32]::MaxValue -and $number -le [uint32]::MaxValue) {
        return '0x{0:X8}' -f [uint32]$number
    }
    return $number.ToString([Globalization.CultureInfo]::InvariantCulture)
}

function Resolve-SideyInstallerError {
    param(
        $NativeCode,
        [string]$Source = 'UNKNOWN',
        [string]$Stage = 'INSTALL',
        [string]$CategoryHint,
        [string]$Symbol
    )
    $normalizedCode = ConvertTo-SideyNativeCode $NativeCode
    if ($normalizedCode -in @('0', '0x00000000')) {
        return [pscustomobject]@{ Status = 'SUCCESS'; Category = ''; NativeCode = $normalizedCode;
            Source = $Source; Stage = $Stage; Symbol = 'ERROR_SUCCESS' }
    }
    if ($normalizedCode -in @('1641', '3010')) {
        $successSymbol = if ($normalizedCode -eq '1641') { 'ERROR_SUCCESS_REBOOT_INITIATED' } else { 'ERROR_SUCCESS_REBOOT_REQUIRED' }
        return [pscustomobject]@{ Status = 'SUCCESS_REBOOT_REQUIRED'; Category = 'REBOOT_REQUIRED';
            NativeCode = $normalizedCode; Source = $Source; Stage = $Stage; Symbol = $successSymbol }
    }

    $definition = $script:SideyInstallerErrorDefinitions[$normalizedCode]
    if ($null -ne $definition) {
        return [pscustomobject]@{ Status = 'FAILED'; Category = $definition[0]; NativeCode = $normalizedCode;
            Source = $Source; Stage = $Stage; Symbol = $definition[1] }
    }

    $category = if ($CategoryHint -in $script:SideyInstallerCategories) {
        $CategoryHint
    }
    elseif ($Stage -eq 'DOWNLOAD') {
        'DOWNLOAD_FAILED'
    }
    else {
        'UNKNOWN_ERROR'
    }
    return [pscustomobject]@{ Status = 'FAILED'; Category = $category; NativeCode = $normalizedCode;
        Source = $Source; Stage = $Stage; Symbol = $Symbol }
}

function New-SideyInstallerException {
    param(
        [string]$Message,
        [Exception]$InnerException,
        $NativeCode,
        [string]$Source,
        [string]$Stage,
        [string]$CategoryHint,
        [string]$Target,
        [string]$CommandDescription,
        [string]$ExitCode,
        [string]$Symbol
    )
    $exception = [Exception]::new($Message, $InnerException)
    foreach ($entry in @{
            NativeCode = $NativeCode; Source = $Source; Stage = $Stage; CategoryHint = $CategoryHint;
            Target = $Target; CommandDescription = $CommandDescription; ExitCode = $ExitCode; Symbol = $Symbol
        }.GetEnumerator()) {
        if ($null -ne $entry.Value -and -not [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            $exception.Data["SideyInstaller$($entry.Key)"] = $entry.Value
        }
    }
    return $exception
}

function Get-SideyExceptionData {
    param([Exception]$Exception, [string]$Name)
    $current = $Exception
    while ($null -ne $current) {
        $key = "SideyInstaller$Name"
        if ($current.Data.Contains($key)) { return $current.Data[$key] }
        $current = $current.InnerException
    }
    return $null
}

function Get-SideyExceptionNativeCode {
    param([Exception]$Exception)
    $explicit = Get-SideyExceptionData $Exception 'NativeCode'
    if ($null -ne $explicit) { return $explicit }
    $current = $Exception
    while ($null -ne $current) {
        if ($current -is [ComponentModel.Win32Exception] -and $current.NativeErrorCode -ne 0) {
            return $current.NativeErrorCode
        }
        if ($current.HResult -ne 0) { $fallback = $current.HResult }
        $current = $current.InnerException
    }
    return $fallback
}

function Get-SideyDownloadCategoryHint {
    param([Exception]$Exception)
    $networkStatuses = @(
        [Net.WebExceptionStatus]::ConnectFailure,
        [Net.WebExceptionStatus]::ConnectionClosed,
        [Net.WebExceptionStatus]::KeepAliveFailure,
        [Net.WebExceptionStatus]::NameResolutionFailure,
        [Net.WebExceptionStatus]::ProxyNameResolutionFailure,
        [Net.WebExceptionStatus]::ReceiveFailure,
        [Net.WebExceptionStatus]::SendFailure,
        [Net.WebExceptionStatus]::Timeout
    )
    $current = $Exception
    while ($null -ne $current) {
        if ($current -is [Net.WebException] -and $current.Status -in $networkStatuses) {
            return 'NETWORK_ERROR'
        }
        $current = $current.InnerException
    }
    return 'DOWNLOAD_FAILED'
}

function ConvertTo-SideySafeLogValue {
    param($Value)
    if ($null -eq $Value) { return '' }
    $text = ([string]$Value) -replace '[\r\n\t]+', ' '
    foreach ($path in @([Environment]::GetFolderPath('UserProfile'), [IO.Path]::GetTempPath().TrimEnd('\'))) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $replacement = if ($path -eq [Environment]::GetFolderPath('UserProfile')) { '%USERPROFILE%' } else { '%TEMP%' }
            $text = [regex]::Replace($text, [regex]::Escape($path), $replacement,
                [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    $text = [regex]::Replace($text, 'https://[^\s?]+\?[^\s]+', {
        param($match)
        try { return ([uri]$match.Value).GetLeftPart([UriPartial]::Path) } catch { return 'https://[redacted]' }
    })
    if ($text.Length -gt 1000) { $text = $text.Substring(0, 1000) }
    return $text
}

function Write-SideyInstallerLog {
    param($Result, [string]$LogPath)
    if ([string]::IsNullOrWhiteSpace($LogPath)) { return }
    $directory = Split-Path -Parent $LogPath
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }
    $section = if ($Result.Status -eq 'FAILED') { 'InstallerError' } else { 'InstallerResult' }
    $lines = @(
        "[$section]",
        "timestamp=$([DateTime]::UtcNow.ToString('o', [Globalization.CultureInfo]::InvariantCulture))",
        "status=$(ConvertTo-SideySafeLogValue $Result.Status)",
        "category=$(ConvertTo-SideySafeLogValue $Result.Category)",
        "source=$(ConvertTo-SideySafeLogValue $Result.Source)",
        "nativeCode=$(ConvertTo-SideySafeLogValue $Result.NativeCode)",
        "stage=$(ConvertTo-SideySafeLogValue $Result.Stage)",
        "message=$(ConvertTo-SideySafeLogValue $Result.Symbol)",
        "detail=$(ConvertTo-SideySafeLogValue $Result.Message)",
        "target=$(ConvertTo-SideySafeLogValue $Result.Target)",
        "command=$(ConvertTo-SideySafeLogValue $Result.CommandDescription)",
        "exitCode=$(ConvertTo-SideySafeLogValue $Result.ExitCode)",
        "windowsVersion=$(ConvertTo-SideySafeLogValue ([Environment]::OSVersion.VersionString))",
        "installerVersion=$(ConvertTo-SideySafeLogValue $Result.InstallerVersion)",
        ''
    )
    Add-Content -LiteralPath $LogPath -Value $lines -Encoding UTF8
}

function Write-SideyInstallerResult {
    param($Result, [string]$ResultPath, [string]$LogPath)
    if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
        $directory = Split-Path -Parent $ResultPath
        if (-not [string]::IsNullOrWhiteSpace($directory)) {
            [IO.Directory]::CreateDirectory($directory) | Out-Null
        }
        $lines = @(
            '[InstallerResult]',
            "status=$(ConvertTo-SideySafeLogValue $Result.Status)",
            "category=$(ConvertTo-SideySafeLogValue $Result.Category)",
            "source=$(ConvertTo-SideySafeLogValue $Result.Source)",
            "nativeCode=$(ConvertTo-SideySafeLogValue $Result.NativeCode)",
            "stage=$(ConvertTo-SideySafeLogValue $Result.Stage)",
            "symbol=$(ConvertTo-SideySafeLogValue $Result.Symbol)",
            "detail=$(ConvertTo-SideySafeLogValue $Result.Message)",
            "target=$(ConvertTo-SideySafeLogValue $Result.Target)",
            "command=$(ConvertTo-SideySafeLogValue $Result.CommandDescription)",
            "exitCode=$(ConvertTo-SideySafeLogValue $Result.ExitCode)",
            "logPath=$(ConvertTo-SideySafeLogValue $LogPath)"
        )
        [IO.File]::WriteAllLines($ResultPath, $lines, [Text.Encoding]::Unicode)
    }
    try {
        Write-SideyInstallerLog $Result $LogPath
    }
    catch {
        # A logging failure must not hide the original installation result or
        # turn a successful prerequisite operation into a failed installation.
        Write-Host 'Installer diagnostic log could not be written.'
    }
}

function ConvertTo-SideyInstallerFailureResult {
    param([Exception]$Exception, [string]$InstallerVersion)
    $nativeCode = Get-SideyExceptionNativeCode $Exception
    $source = [string](Get-SideyExceptionData $Exception 'Source')
    $stage = [string](Get-SideyExceptionData $Exception 'Stage')
    $categoryHint = [string](Get-SideyExceptionData $Exception 'CategoryHint')
    $symbol = [string](Get-SideyExceptionData $Exception 'Symbol')
    if ([string]::IsNullOrWhiteSpace($source)) { $source = 'POWERSHELL' }
    if ([string]::IsNullOrWhiteSpace($stage)) { $stage = 'INSTALL' }
    $normalized = Resolve-SideyInstallerError $nativeCode $source $stage $categoryHint $symbol
    return [pscustomobject]@{
        Status = $normalized.Status; Category = $normalized.Category; NativeCode = $normalized.NativeCode
        Source = $normalized.Source; Stage = $normalized.Stage; Symbol = $normalized.Symbol
        Message = $Exception.Message
        Target = Get-SideyExceptionData $Exception 'Target'
        CommandDescription = Get-SideyExceptionData $Exception 'CommandDescription'
        ExitCode = Get-SideyExceptionData $Exception 'ExitCode'
        InstallerVersion = $InstallerVersion
    }
}

function New-SideyInstallerResult {
    param($NativeCode, [string]$Source, [string]$Stage, [string]$CategoryHint,
        [string]$Target, [string]$CommandDescription, [string]$ExitCode,
        [string]$Message, [string]$InstallerVersion)
    $normalized = Resolve-SideyInstallerError $NativeCode $Source $Stage $CategoryHint
    return [pscustomobject]@{
        Status = $normalized.Status; Category = $normalized.Category; NativeCode = $normalized.NativeCode
        Source = $normalized.Source; Stage = $normalized.Stage; Symbol = $normalized.Symbol
        Message = $Message; Target = $Target; CommandDescription = $CommandDescription
        ExitCode = $ExitCode; InstallerVersion = $InstallerVersion
    }
}
