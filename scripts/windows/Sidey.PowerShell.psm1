#requires -Version 5.1

Set-StrictMode -Version 3.0

function Invoke-SideyNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [AllowEmptyCollection()]
        [string[]]$ArgumentList = @(),

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Description
    )

    & $FilePath @ArgumentList
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$Description failed with exit code $exitCode."
    }
}

function ConvertTo-SideyWindowsArgument {
    param([AllowEmptyString()][string]$Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    # Start-Process accepts one native command-line string on Windows. Quote
    # embedded quotes and trailing backslashes using CommandLineToArgvW rules.
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Invoke-SideyWindowsProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [AllowEmptyCollection()]
        [string[]]$ArgumentList = @()
    )

    $startParameters = @{
        FilePath = $FilePath
        WindowStyle = 'Hidden'
        Wait = $true
        PassThru = $true
    }
    if ($ArgumentList.Count -gt 0) {
        $startParameters.ArgumentList = ($ArgumentList | ForEach-Object {
            ConvertTo-SideyWindowsArgument $_
        }) -join ' '
    }
    $process = Start-Process @startParameters
    try {
        return $process.ExitCode
    }
    finally {
        $process.Dispose()
    }
}

Export-ModuleMember -Function Invoke-SideyNativeCommand, Invoke-SideyWindowsProcess
