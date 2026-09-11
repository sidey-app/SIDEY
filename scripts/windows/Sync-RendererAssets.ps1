#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$repositoryRootPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$canonicalAssetDirectory = Join-Path $repositoryRootPath 'assets/v1'
$windowsAssetDirectory = Join-Path $repositoryRootPath 'windows/src/Sidey.Overlay/Assets'
$manifestPath = Join-Path $canonicalAssetDirectory 'manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Copy-SideyRendererAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory,

        [Parameter(Mandatory = $true)]
        [string]$OutputName,

        [switch]$CreateBgra,

        [switch]$BottomUp
    )

    [IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
    Copy-Item `
        -LiteralPath $SourcePath `
        -Destination (Join-Path $OutputDirectory "$OutputName.png") `
        -Force

    if (-not $CreateBgra) {
        return
    }

    $bitmap = $null
    try {
        $bitmap = [Drawing.Bitmap]::FromFile($SourcePath)
        $bytes = [byte[]]::new($bitmap.Width * $bitmap.Height * 4)
        $offset = 0
        $rowIndexes = if ($BottomUp) {
            ($bitmap.Height - 1)..0
        }
        else {
            0..($bitmap.Height - 1)
        }

        foreach ($rowIndex in $rowIndexes) {
            for ($columnIndex = 0; $columnIndex -lt $bitmap.Width; $columnIndex++) {
                $pixel = $bitmap.GetPixel($columnIndex, $rowIndex)
                $bytes[$offset] = $pixel.B
                $bytes[$offset + 1] = $pixel.G
                $bytes[$offset + 2] = $pixel.R
                $bytes[$offset + 3] = $pixel.A
                $offset += 4
            }
        }

        [IO.File]::WriteAllBytes(
            (Join-Path $OutputDirectory "$OutputName.bgra"),
            $bytes)
    }
    finally {
        if ($null -ne $bitmap) {
            $bitmap.Dispose()
        }
    }
}

foreach ($character in $manifest.characters) {
    if ($character.supported_platforms -notcontains 'windows') {
        continue
    }

    $outputDirectory = Join-Path $windowsAssetDirectory "Characters/$($character.id)"
    Copy-SideyRendererAsset `
        -SourcePath (Join-Path $canonicalAssetDirectory $character.base.path) `
        -OutputDirectory $outputDirectory `
        -OutputName 'base' `
        -CreateBgra
    Copy-SideyRendererAsset `
        -SourcePath (Join-Path $canonicalAssetDirectory $character.throw_hit.path) `
        -OutputDirectory $outputDirectory `
        -OutputName 'throw_hit' `
        -CreateBgra `
        -BottomUp
}

foreach ($throwable in $manifest.throwables) {
    if ($throwable.supported_platforms -notcontains 'windows') {
        continue
    }

    $outputDirectory = Join-Path $windowsAssetDirectory "Throwables/$($throwable.id)"
    Copy-SideyRendererAsset `
        -SourcePath (Join-Path $canonicalAssetDirectory $throwable.sprite.path) `
        -OutputDirectory $outputDirectory `
        -OutputName 'sprite' `
        -CreateBgra `
        -BottomUp
    $emitterProperty = $throwable.PSObject.Properties['emitter']
    if ($null -ne $emitterProperty) {
        Copy-SideyRendererAsset `
            -SourcePath (Join-Path $canonicalAssetDirectory $emitterProperty.Value.path) `
            -OutputDirectory $outputDirectory `
            -OutputName 'emitter' `
            -CreateBgra `
            -BottomUp
    }
    $previewProperty = $throwable.PSObject.Properties['preview']
    if ($null -ne $previewProperty) {
        Copy-SideyRendererAsset `
            -SourcePath (Join-Path $canonicalAssetDirectory $previewProperty.Value.path) `
            -OutputDirectory $outputDirectory `
            -OutputName 'preview'
    }
}

foreach ($bubble in $manifest.bubbles) {
    if ($bubble.supported_platforms -notcontains 'windows') {
        continue
    }

    $outputDirectory = Join-Path $windowsAssetDirectory "Bubbles/$($bubble.id)"
    Copy-SideyRendererAsset `
        -SourcePath (Join-Path $canonicalAssetDirectory $bubble.decoration.path) `
        -OutputDirectory $outputDirectory `
        -OutputName 'decoration' `
        -CreateBgra
    Copy-SideyRendererAsset `
        -SourcePath (Join-Path $canonicalAssetDirectory $bubble.preview.path) `
        -OutputDirectory $outputDirectory `
        -OutputName 'preview'
}

Write-Host 'Synchronized Windows renderer assets from assets/v1/manifest.json.'
