[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function New-SideyCompactIcon {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(16, 20, 24)]
        [int] $Size
    )

    $bitmap = [System.Drawing.Bitmap]::new(
        $Size,
        $Size,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        $padding = [Math]::Max(1, [int] [Math]::Round($Size * 0.08))
        $tailHeight = [Math]::Max(3, [int] [Math]::Round($Size * 0.17))
        $bubble = [System.Drawing.RectangleF]::new(
            $padding,
            $padding,
            $Size - (2 * $padding),
            $Size - (2 * $padding) - $tailHeight)
        $radius = [Math]::Max(4, [int] [Math]::Round($Size * 0.22))
        $diameter = 2 * $radius
        $bubblePath = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $bubbleBrush = [System.Drawing.SolidBrush]::new(
            [System.Drawing.Color]::FromArgb(255, 132, 134, 232))
        try {
            $bubblePath.AddArc($bubble.Left, $bubble.Top, $diameter, $diameter, 180, 90)
            $bubblePath.AddArc($bubble.Right - $diameter, $bubble.Top, $diameter, $diameter, 270, 90)
            $bubblePath.AddArc(
                $bubble.Right - $diameter,
                $bubble.Bottom - $diameter,
                $diameter,
                $diameter,
                0,
                90)
            $bubblePath.AddArc($bubble.Left, $bubble.Bottom - $diameter, $diameter, $diameter, 90, 90)
            $bubblePath.CloseFigure()
            $graphics.FillPath($bubbleBrush, $bubblePath)

            $tail = [System.Drawing.PointF[]] @(
                [System.Drawing.PointF]::new($bubble.Left + ($bubble.Width * 0.22), $bubble.Bottom - 1),
                [System.Drawing.PointF]::new($bubble.Left + ($bubble.Width * 0.48), $bubble.Bottom - 1),
                [System.Drawing.PointF]::new($bubble.Left + ($bubble.Width * 0.22), $Size - $padding)
            )
            $graphics.FillPolygon($bubbleBrush, $tail)
        }
        finally {
            $bubbleBrush.Dispose()
            $bubblePath.Dispose()
        }

        # A single pixel S stays identifiable where the full wordmark and two pets cannot.
        $cellSize = if ($Size -ge 24) { 3 } else { 2 }
        $glyphWidth = 3 * $cellSize
        $glyphHeight = 5 * $cellSize
        $glyphLeft = [int] [Math]::Round(($Size - $glyphWidth) / 2)
        $glyphTop = [int] [Math]::Round($bubble.Top + (($bubble.Height - $glyphHeight) / 2))
        $glyphRows = @(
            '111',
            '100',
            '111',
            '001',
            '111'
        )
        $glyphBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
        try {
            for ($row = 0; $row -lt $glyphRows.Count; $row++) {
                for ($column = 0; $column -lt 3; $column++) {
                    if ($glyphRows[$row][$column] -eq '1') {
                        $graphics.FillRectangle(
                            $glyphBrush,
                            $glyphLeft + ($column * $cellSize),
                            $glyphTop + ($row * $cellSize),
                            $cellSize,
                            $cellSize)
                    }
                }
            }
        }
        finally {
            $glyphBrush.Dispose()
        }
    }
    finally {
        $graphics.Dispose()
    }

    return $bitmap
}

$iconsDirectory = Join-Path $RepositoryRoot 'windows\src\Sidey.App\Assets\Icons'
$sourcePath = Join-Path $iconsDirectory 'SideyAppIcon.png'
$outputPath = Join-Path $iconsDirectory 'SideyAppIcon.ico'
$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256

$source = [System.Drawing.Image]::FromFile($sourcePath)
try {
    $images = foreach ($size in $sizes) {
        $bitmap = if ($size -le 24) {
            New-SideyCompactIcon -Size $size
        }
        else {
            [System.Drawing.Bitmap]::new(
                $size,
                $size,
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        }
        try {
            if ($size -gt 24) {
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                try {
                    $graphics.Clear([System.Drawing.Color]::Transparent)
                    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                    $graphics.DrawImage($source, 0, 0, $size, $size)
                }
                finally {
                    $graphics.Dispose()
                }
            }

            $pngPath = Join-Path $iconsDirectory "SideyAppIcon-$size.png"
            $bitmap.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
            [PSCustomObject]@{
                Size = $size
                Bytes = [System.IO.File]::ReadAllBytes($pngPath)
            }
        }
        finally {
            $bitmap.Dispose()
        }
    }
}
finally {
    $source.Dispose()
}

$stream = [System.IO.File]::Create($outputPath)
$writer = [System.IO.BinaryWriter]::new($stream)
try {
    $writer.Write([uint16] 0)
    $writer.Write([uint16] 1)
    $writer.Write([uint16] $images.Count)

    $offset = 6 + (16 * $images.Count)
    foreach ($image in $images) {
        $dimension = if ($image.Size -eq 256) { 0 } else { $image.Size }
        $writer.Write([byte] $dimension)
        $writer.Write([byte] $dimension)
        $writer.Write([byte] 0)
        $writer.Write([byte] 0)
        $writer.Write([uint16] 1)
        $writer.Write([uint16] 32)
        $writer.Write([uint32] $image.Bytes.Length)
        $writer.Write([uint32] $offset)
        $offset += $image.Bytes.Length
    }

    foreach ($image in $images) {
        $writer.Write($image.Bytes)
    }
}
finally {
    $writer.Dispose()
    $stream.Dispose()
}

Write-Output $outputPath
