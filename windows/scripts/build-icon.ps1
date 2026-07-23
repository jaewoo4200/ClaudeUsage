[CmdletBinding()]
param(
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Split-Path -Parent $PSScriptRoot) "src\ClaudeUsage.Windows\Assets\App.ico"
}

$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$frames = [System.Collections.Generic.List[byte[]]]::new()

foreach ($size in $sizes) {
    $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)

        $inset = [Math]::Max(1.0, $size * 0.055)
        $diameter = $size - (2 * $inset)
        $background = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 217, 119, 87))
        try {
            $graphics.FillEllipse($background, [single]$inset, [single]$inset, [single]$diameter, [single]$diameter)
        }
        finally {
            $background.Dispose()
        }

        $ringInset = $size * 0.21
        $ringDiameter = $size - (2 * $ringInset)
        $ringWidth = [Math]::Max(1.35, $size * 0.075)
        $track = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(76, 255, 255, 255), [single]$ringWidth)
        $progress = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(245, 255, 255, 255), [single]$ringWidth)
        try {
            $track.StartCap = $track.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $progress.StartCap = $progress.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $graphics.DrawEllipse($track, [single]$ringInset, [single]$ringInset, [single]$ringDiameter, [single]$ringDiameter)
            $graphics.DrawArc($progress, [single]$ringInset, [single]$ringInset, [single]$ringDiameter, [single]$ringDiameter, -90, 277)
        }
        finally {
            $track.Dispose()
            $progress.Dispose()
        }

        if ($size -ge 32) {
            $font = [System.Drawing.Font]::new("Segoe UI", [single]($size * 0.30), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
            $brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
            $format = [System.Drawing.StringFormat]::new()
            try {
                $format.Alignment = [System.Drawing.StringAlignment]::Center
                $format.LineAlignment = [System.Drawing.StringAlignment]::Center
                $rectangle = [System.Drawing.RectangleF]::new(0, [single]($size * 0.015), $size, $size)
                $graphics.DrawString("C", $font, $brush, $rectangle, $format)
            }
            finally {
                $format.Dispose()
                $brush.Dispose()
                $font.Dispose()
            }
        }

        $stream = [System.IO.MemoryStream]::new()
        $frameWriter = [System.IO.BinaryWriter]::new($stream)
        try {
            $pixelBytes = $size * $size * 4
            $maskStride = [Math]::Floor(($size + 31) / 32) * 4
            $maskBytes = $maskStride * $size

            $frameWriter.Write([int32]40)
            $frameWriter.Write([int32]$size)
            $frameWriter.Write([int32]($size * 2))
            $frameWriter.Write([uint16]1)
            $frameWriter.Write([uint16]32)
            $frameWriter.Write([uint32]0)
            $frameWriter.Write([uint32]$pixelBytes)
            $frameWriter.Write([int32]0)
            $frameWriter.Write([int32]0)
            $frameWriter.Write([uint32]0)
            $frameWriter.Write([uint32]0)

            for ($y = $size - 1; $y -ge 0; $y--) {
                for ($x = 0; $x -lt $size; $x++) {
                    $color = $bitmap.GetPixel($x, $y)
                    $frameWriter.Write([byte]$color.B)
                    $frameWriter.Write([byte]$color.G)
                    $frameWriter.Write([byte]$color.R)
                    $frameWriter.Write([byte]$color.A)
                }
            }

            $frameWriter.Write([byte[]]::new($maskBytes))
            $frameWriter.Flush()
            $frames.Add($stream.ToArray())
        }
        finally {
            $frameWriter.Dispose()
            $stream.Dispose()
        }
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$directory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$file = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
$writer = [System.IO.BinaryWriter]::new($file)
try {
    $writer.Write([uint16]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]$frames.Count)

    $offset = 6 + (16 * $frames.Count)
    for ($index = 0; $index -lt $frames.Count; $index++) {
        $size = $sizes[$index]
        $writer.Write([byte]($(if ($size -eq 256) { 0 } else { $size })))
        $writer.Write([byte]($(if ($size -eq 256) { 0 } else { $size })))
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]32)
        $writer.Write([uint32]$frames[$index].Length)
        $writer.Write([uint32]$offset)
        $offset += $frames[$index].Length
    }

    foreach ($frame in $frames) {
        $writer.Write($frame)
    }
}
finally {
    $writer.Dispose()
    $file.Dispose()
}

Write-Output $OutputPath
