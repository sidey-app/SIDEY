#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$SourceIconPath,
    [string]$OutputPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repositoryRootPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

if ([string]::IsNullOrWhiteSpace($SourceIconPath)) {
    $SourceIconPath = Join-Path $repositoryRootPath 'windows/src/Sidey.App/Assets/Icons/SideyAppIcon.png'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repositoryRootPath 'windows/installer/Sidey.Setup/SideyWelcome.bmp'
}

$sourceIconFilePath = (Resolve-Path -LiteralPath $SourceIconPath).Path
$outputFilePath = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFilePath)) | Out-Null

Add-Type -AssemblyName System.Drawing

$canvasWidth = 164
$canvasHeight = 314
$artworkSize = 160
$artworkLeft = [int](($canvasWidth - $artworkSize) / 2)
$artworkTop = [int](($canvasHeight - $artworkSize) / 2)
$sourceBitmap = $null
$canvas = $null
$graphics = $null

try {
    $sourceBitmap = [Drawing.Bitmap]::FromFile($sourceIconFilePath)
    if ($sourceBitmap.Width -ne 256 -or $sourceBitmap.Height -ne 256) {
        throw "SIDEY installer artwork requires a 256x256 source icon: $sourceIconFilePath"
    }

    $canvas = [Drawing.Bitmap]::new(
        $canvasWidth,
        $canvasHeight,
        [Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $canvas.SetResolution(96, 96)
    $graphics = [Drawing.Graphics]::FromImage($canvas)
    $graphics.Clear([Drawing.Color]::White)
    $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::Half

    $destinationRectangle = [Drawing.Rectangle]::new(
        $artworkLeft,
        $artworkTop,
        $artworkSize,
        $artworkSize)
    $graphics.DrawImage(
        $sourceBitmap,
        $destinationRectangle,
        0,
        0,
        $sourceBitmap.Width,
        $sourceBitmap.Height,
        [Drawing.GraphicsUnit]::Pixel)
    $canvas.Save($outputFilePath, [Drawing.Imaging.ImageFormat]::Bmp)
}
finally {
    if ($null -ne $graphics) {
        $graphics.Dispose()
    }
    if ($null -ne $canvas) {
        $canvas.Dispose()
    }
    if ($null -ne $sourceBitmap) {
        $sourceBitmap.Dispose()
    }
}

Write-Host "Created SIDEY installer artwork: $outputFilePath"
