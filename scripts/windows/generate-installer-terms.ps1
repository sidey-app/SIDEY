[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceHtml,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$resolvedSourceHtml = (Resolve-Path -LiteralPath $SourceHtml).Path
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
$html = Get-Content -LiteralPath $resolvedSourceHtml -Raw -Encoding UTF8
$mainMatch = [regex]::Match(
    $html,
    '<main\b[^>]*\bid=["'']main["''][^>]*>(?<content>.*?)</main>',
    [Text.RegularExpressions.RegexOptions]::Singleline -bor
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)

if (-not $mainMatch.Success) {
    throw "Unable to find the terms document body in $resolvedSourceHtml"
}

$terms = $mainMatch.Groups['content'].Value
$sectionCount = [regex]::Matches(
    $terms,
    '<section\b',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase).Count
if ($sectionCount -ne 9) {
    throw "Expected 9 terms sections but found $sectionCount in $resolvedSourceHtml"
}

$terms = [regex]::Replace(
    $terms,
    '<br\s*/?>',
    "`n",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase)
$terms = [regex]::Replace(
    $terms,
    '</(?:h1|h2|p|dt|dd|header|section|div)\s*>',
    "`n",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase)
$terms = [regex]::Replace($terms, '<[^>]+>', '')
$terms = [Net.WebUtility]::HtmlDecode($terms)

$lines = @($terms -split '\r?\n' |
    ForEach-Object { [regex]::Replace($_.Trim(), '\s+', ' ') } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$plainText = ($lines -join "`r`n`r`n") + "`r`n"

foreach ($requiredText in @(
    'SIDEY',
    '1.',
    '9.',
    '388-53-01259',
    'ryu200112@gmail.com')) {
    if ($plainText.IndexOf($requiredText, [StringComparison]::Ordinal) -lt 0) {
        throw "Generated installer terms are missing required text: $requiredText"
    }
}

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($resolvedOutputPath)) | Out-Null
[IO.File]::WriteAllText(
    $resolvedOutputPath,
    $plainText,
    [Text.UTF8Encoding]::new($false))

Write-Host "Created SIDEY installer terms: $resolvedOutputPath"
