[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceMarkdown,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$resolvedSourceMarkdown = (Resolve-Path -LiteralPath $SourceMarkdown).Path
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
$markdown = Get-Content -LiteralPath $resolvedSourceMarkdown -Raw -Encoding UTF8

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

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($resolvedOutputPath)) | Out-Null
[IO.File]::WriteAllText(
    $resolvedOutputPath,
    $plainText,
    [Text.UTF8Encoding]::new($true))

Write-Host "Created SIDEY installer terms: $resolvedOutputPath"
