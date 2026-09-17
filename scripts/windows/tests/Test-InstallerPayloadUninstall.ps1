#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDirectory,

    [Parameter(Mandatory = $true)]
    [string]$UninstallFilesIncludePath,

    [Parameter(Mandatory = $true)]
    [string]$UninstallDirectoriesIncludePath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$publishDirectoryPath = (Resolve-Path -LiteralPath $PublishDirectory).Path
$uninstallFilesIncludeFilePath = (Resolve-Path -LiteralPath $UninstallFilesIncludePath).Path
$uninstallDirectoriesIncludeFilePath = (
    Resolve-Path -LiteralPath $UninstallDirectoriesIncludePath).Path
$uninstallerPath = Join-Path $publishDirectoryPath 'Uninstall.exe'

function Get-SideyRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $basePathWithSeparator = [IO.Path]::GetFullPath($BasePath)
    $separator = [IO.Path]::DirectorySeparatorChar.ToString()
    if (-not $basePathWithSeparator.EndsWith(
        $separator,
        [StringComparison]::Ordinal)) {
        $basePathWithSeparator += $separator
    }

    $baseUri = [Uri]::new($basePathWithSeparator)
    $targetUri = [Uri]::new([IO.Path]::GetFullPath($TargetPath))
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace(
        '/',
        [IO.Path]::DirectorySeparatorChar)
}

function ConvertTo-NsisLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)

    return $Value.Replace('$', '$$').Replace('"', '$\"')
}

$payloadFiles = @(Get-ChildItem -LiteralPath $publishDirectoryPath -Recurse -File |
    Where-Object {
        $_.Extension -ne '.pdb' -and
        -not $_.FullName.Equals($uninstallerPath, [StringComparison]::OrdinalIgnoreCase)
    })
$expectedDeleteLines = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
$expectedDirectories = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)

foreach ($file in $payloadFiles) {
    $relativePath = Get-SideyRelativePath $publishDirectoryPath $file.FullName
    [void]$expectedDeleteLines.Add(
        "Delete `"`$INSTDIR\$(ConvertTo-NsisLiteral $relativePath)`"")

    $directory = Split-Path $relativePath -Parent
    while (-not [string]::IsNullOrWhiteSpace($directory)) {
        [void]$expectedDirectories.Add($directory)
        $directory = Split-Path $directory -Parent
    }
}

# Runtime contains SIDEY.UninstallHelper.exe, which is installed outside the
# generated payload manifest and removed by the NSIS section after the manifest
# succeeds. Keeping that directory out of the manifest preserves retry support.
[void]$expectedDirectories.Remove('Runtime')

$expectedRmDirLines = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
foreach ($directory in $expectedDirectories) {
    [void]$expectedRmDirLines.Add(
        "RMDir `"`$INSTDIR\$(ConvertTo-NsisLiteral $directory)`"")
}

$deleteLines = @(Get-Content -LiteralPath $uninstallFilesIncludeFilePath -Encoding UTF8)
$rmDirLines = @(Get-Content -LiteralPath $uninstallDirectoriesIncludeFilePath -Encoding UTF8)
$unexpectedDeleteLines = @($deleteLines | Where-Object {
    -not $_.StartsWith('Delete ', [StringComparison]::Ordinal)
})
if ($unexpectedDeleteLines.Count -gt 0) {
    throw "Unexpected uninstall file operation: $($unexpectedDeleteLines[0])"
}
$unexpectedRmDirLines = @($rmDirLines | Where-Object {
    -not $_.StartsWith('RMDir ', [StringComparison]::Ordinal)
})
if ($unexpectedRmDirLines.Count -gt 0) {
    throw "Unexpected uninstall directory operation: $($unexpectedRmDirLines[0])"
}
if (@($deleteLines | Select-Object -Unique).Count -ne $deleteLines.Count -or
    @($rmDirLines | Select-Object -Unique).Count -ne $rmDirLines.Count) {
    throw 'The uninstall manifest contains duplicate operations.'
}

$deleteDifferences = @(Compare-Object @($expectedDeleteLines) $deleteLines)
if ($deleteDifferences.Count -gt 0) {
    throw "The uninstall manifest does not match the packaged files: $($deleteDifferences | Out-String)"
}
$directoryDifferences = @(Compare-Object @($expectedRmDirLines) $rmDirLines)
if ($directoryDifferences.Count -gt 0) {
    throw "The uninstall manifest does not cover every payload directory: $($directoryDifferences | Out-String)"
}
if (@($rmDirLines | Where-Object { $_ -match '^RMDir\s+/r\b' }).Count -gt 0) {
    throw 'Payload directories must use non-recursive RMDir to preserve unowned files.'
}
if (@($deleteLines + $rmDirLines | Where-Object {
    $_ -match '[*?]' -or $_ -match '(^|[\\/])\.\.([\\/]|")'
}).Count -gt 0) {
    throw 'The uninstall manifest must not contain wildcards or parent traversal.'
}

$previousDepth = [int]::MaxValue
$prefixLength = 'RMDir "$INSTDIR\'.Length
foreach ($line in $rmDirLines) {
    $relativeDirectory = $line.Substring($prefixLength, $line.Length - $prefixLength - 1)
    $depth = @($relativeDirectory -split '[\\/]').Count
    if ($depth -gt $previousDepth) {
        throw 'Payload directories must be removed deepest-first.'
    }
    $previousDepth = $depth
}

Write-Host "InstallerPayloadUninstall=true; Files=$($payloadFiles.Count); Directories=$($expectedDirectories.Count)"
