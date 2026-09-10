#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceMarkdownPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$sourceMarkdownFilePath = (Resolve-Path -LiteralPath $SourceMarkdownPath).Path
$outputFilePath = [IO.Path]::GetFullPath($OutputPath)
$markdown = Get-Content -LiteralPath $sourceMarkdownFilePath -Raw -Encoding UTF8

$markdown = [regex]::Replace(
    $markdown,
    '\A---\s*\r?\n.*?\r?\n---\s*\r?\n',
    '',
    [Text.RegularExpressions.RegexOptions]::Singleline)

$terms = [regex]::Replace($markdown, '\[([^\]]+)\]\(([^)]+)\)', '$1 ($2)')
$terms = [regex]::Replace($terms, '^#{1,6}\s+', '', [Text.RegularExpressions.RegexOptions]::Multiline)
$terms = [regex]::Replace($terms, '(?<!\\)[*_]{1,3}', '')
$terms = [regex]::Replace($terms, '<([^>]+)>', '$1')

$lines = @($terms -split '\r?\n' |
    ForEach-Object { [regex]::Replace($_.Trim(), '\s+', ' ') } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$plainText = ($lines -join "`r`n`r`n") + "`r`n"

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFilePath)) | Out-Null
[IO.File]::WriteAllText(
    $outputFilePath,
    $plainText,
    [Text.UTF8Encoding]::new($true))

Write-Host "Created SIDEY installer terms: $outputFilePath"
