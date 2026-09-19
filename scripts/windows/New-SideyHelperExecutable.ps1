#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string[]]$SourcePath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$FileVersion,
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][string]$Description,
    [Parameter(Mandatory = $true)][string]$IconPath,
    [string]$ManifestPath,
    [string]$ResourcePath,
    [string]$ResourceName
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Sidey.PowerShell.psm1') -Force

if ([string]::IsNullOrWhiteSpace($ResourcePath) -ne [string]::IsNullOrWhiteSpace($ResourceName)) {
    throw 'ResourcePath and ResourceName must be supplied together.'
}
[void][Version]::Parse($FileVersion)
$repositoryRootPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$projectPath = Join-Path $repositoryRootPath 'windows/tools/Sidey.HelperBuild/Sidey.HelperBuild.csproj'
$outputFilePath = [IO.Path]::GetFullPath($OutputPath)
if ([IO.Path]::GetExtension($outputFilePath) -ine '.exe') {
    throw 'OutputPath must name an executable.'
}
$sourceFiles = @($SourcePath | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })
if ($sourceFiles.Count -eq 0) { throw 'At least one source file is required.' }
$iconFilePath = (Resolve-Path -LiteralPath $IconPath).Path
$manifestFilePath = if ($ManifestPath) { (Resolve-Path -LiteralPath $ManifestPath).Path } else { $null }
$resourceFilePath = if ($ResourcePath) { (Resolve-Path -LiteralPath $ResourcePath).Path } else { $null }

# All intermediate files and provenance stay outside the published application.
# Unique directories also let independent helper builds run concurrently.
$buildRootPath = Join-Path $repositoryRootPath ('build/windows/helper-build/' + [Guid]::NewGuid().ToString('N'))
$intermediatePath = Join-Path $buildRootPath 'obj/'
$compiledOutputPath = Join-Path $buildRootPath 'bin/'
[IO.Directory]::CreateDirectory($buildRootPath) | Out-Null
$inputsPath = Join-Path $buildRootPath 'inputs.props'

function ConvertTo-MSBuildLiteral([string]$Value) {
    # XML escaping alone does not escape MSBuild item/property expressions.
    foreach ($character in @('%', '$', '@', ';', "'", '(', ')', '?', '*')) {
        $Value = $Value.Replace($character, ('%{0:X2}' -f [int][char]$character))
    }
    return $Value
}

$inputs = [Xml.XmlDocument]::new()
$project = $inputs.CreateElement('Project')
[void]$inputs.AppendChild($project)
$properties = $inputs.CreateElement('PropertyGroup')
[void]$project.AppendChild($properties)
$propertyValues = [ordered]@{
    AssemblyName = [IO.Path]::GetFileNameWithoutExtension($outputFilePath)
    AssemblyTitle = $Title
    Description = $Description
    Version = $Version
    AssemblyVersion = $FileVersion
    FileVersion = $FileVersion
    InformationalVersion = $Version
    ApplicationIcon = $iconFilePath
    PathMap = "$buildRootPath=/_sidey_helper_build,$repositoryRootPath=/_sidey_source"
}
if ($manifestFilePath) { $propertyValues.ApplicationManifest = $manifestFilePath }
foreach ($entry in $propertyValues.GetEnumerator()) {
    $property = $inputs.CreateElement($entry.Key)
    $property.InnerText = ConvertTo-MSBuildLiteral $entry.Value
    [void]$properties.AppendChild($property)
}
$items = $inputs.CreateElement('ItemGroup')
[void]$project.AppendChild($items)
foreach ($source in $sourceFiles) {
    $item = $inputs.CreateElement('Compile')
    $item.SetAttribute('Include', (ConvertTo-MSBuildLiteral $source))
    [void]$items.AppendChild($item)
}
if ($resourceFilePath) {
    $item = $inputs.CreateElement('EmbeddedResource')
    $item.SetAttribute('Include', (ConvertTo-MSBuildLiteral $resourceFilePath))
    $logicalName = $inputs.CreateElement('LogicalName')
    $logicalName.InnerText = ConvertTo-MSBuildLiteral $ResourceName
    [void]$item.AppendChild($logicalName)
    [void]$items.AppendChild($item)
}
$inputs.Save($inputsPath)

# Resolve global.json from windows/ so local and CI builds select the same SDK policy.
Push-Location (Join-Path $repositoryRootPath 'windows')
try {
    $sdkVersion = (Invoke-SideyNativeCommand -FilePath 'dotnet' -ArgumentList @('--version') -Description 'Helper SDK version' | Out-String).Trim()
    Invoke-SideyNativeCommand -FilePath 'dotnet' -ArgumentList @(
        'build', $projectPath, '--configuration', 'Release', '--nologo',
        "-p:HelperBuildInputs=$inputsPath",
        "-p:BaseIntermediateOutputPath=$intermediatePath",
        "-p:MSBuildProjectExtensionsPath=$intermediatePath",
        "-p:OutputPath=$compiledOutputPath"
    ) -Description 'Deterministic .NET Framework helper build'
} finally {
    Pop-Location
}

$builtExecutablePath = Join-Path $compiledOutputPath ([IO.Path]::GetFileName($outputFilePath))
if (-not (Test-Path -LiteralPath $builtExecutablePath -PathType Leaf)) {
    throw "Helper executable was not produced: $builtExecutablePath"
}

function Get-InputEvidence([string]$Path) {
    # Publishing can start Windows PowerShell from pwsh with its module path.
    # Use the runtime directly instead of relying on Get-FileHash autoloading.
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
        return [ordered]@{ path = $Path; sha256 = $hash }
    } finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}
$referencePaths = @(Get-Content -LiteralPath (Join-Path $intermediatePath 'references.txt') -Encoding UTF8 | Sort-Object -Unique)
$buildEvidence = [ordered]@{
    schemaVersion = 1
    sdkVersion = $sdkVersion
    targetFramework = 'net472'
    referenceAssembliesPackage = 'Microsoft.NETFramework.ReferenceAssemblies/1.0.3'
    version = $Version
    fileVersion = $FileVersion
    project = Get-InputEvidence $projectPath
    builder = Get-InputEvidence $PSCommandPath
    sources = @($sourceFiles | ForEach-Object { Get-InputEvidence $_ })
    icon = Get-InputEvidence $iconFilePath
    manifest = if ($manifestFilePath) { Get-InputEvidence $manifestFilePath } else { $null }
    resource = if ($resourceFilePath) { Get-InputEvidence $resourceFilePath } else { $null }
    references = @($referencePaths | ForEach-Object { Get-InputEvidence $_ })
    output = Get-InputEvidence $builtExecutablePath
}
$evidencePath = Join-Path $buildRootPath 'build-manifest.json'
[IO.File]::WriteAllText($evidencePath, ($buildEvidence | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFilePath)) | Out-Null
Copy-Item -LiteralPath $builtExecutablePath -Destination $outputFilePath -Force
Write-Host "HelperExecutable=$outputFilePath"
Write-Host "HelperBuildManifest=$evidencePath"
