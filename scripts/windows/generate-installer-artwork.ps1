[CmdletBinding()]
param(
    [string]$SourceIcon,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

if ([string]::IsNullOrWhiteSpace($SourceIcon)) {
    $SourceIcon = Join-Path $repositoryRoot 'windows/src/Sidey.App/Assets/Icons/SideyAppIcon.png'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repositoryRoot 'windows/installer/Sidey.Setup/SideyWelcome.bmp'
}

$resolvedSourceIcon = (Resolve-Path -LiteralPath $SourceIcon).Path
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($resolvedOutputPath)) | Out-Null

Add-Type -AssemblyName System.Drawing

$canvasWidth = 164
$canvasHeight = 314
$artworkSize = 160
$artworkLeft = [int](($canvasWidth - $artworkSize) / 2)
$artworkTop = [int](($canvasHeight - $artworkSize) / 2)
$source = $null
$canvas = $null
$graphics = $null

try {
    $source = [Drawing.Bitmap]::FromFile($resolvedSourceIcon)
    if ($source.Width -ne 256 -or $source.Height -ne 256) {
        throw "SIDEY installer artwork requires a 256x256 source icon: $resolvedSourceIcon"
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

    $destination = [Drawing.Rectangle]::new(
        $artworkLeft,
        $artworkTop,
        $artworkSize,
        $artworkSize)
    $graphics.DrawImage(
        $source,
        $destination,
        0,
        0,
        $source.Width,
        $source.Height,
        [Drawing.GraphicsUnit]::Pixel)
    $canvas.Save($resolvedOutputPath, [Drawing.Imaging.ImageFormat]::Bmp)
}
finally {
    if ($null -ne $graphics) {
        $graphics.Dispose()
    }
    if ($null -ne $canvas) {
        $canvas.Dispose()
    }
    if ($null -ne $source) {
        $source.Dispose()
    }
}

Write-Host "Created SIDEY installer artwork: $resolvedOutputPath"
