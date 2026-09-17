[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$outputPath = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null

function New-ClaudeUsageLogo {
    param(
        [Parameter(Mandatory)] [int]$Width,
        [Parameter(Mandatory)] [int]$Height,
        [Parameter(Mandatory)] [string]$Path
    )

    $bitmap = [System.Drawing.Bitmap]::new(
        $Width,
        $Height,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.Clear([System.Drawing.Color]::Transparent)

        $canvas = [Math]::Min($Width, $Height)
        $diameter = [single]($canvas * 0.78)
        $left = [single](($Width - $diameter) / 2.0)
        $top = [single](($Height - $diameter) / 2.0)
        $background = [System.Drawing.SolidBrush]::new(
            [System.Drawing.Color]::FromArgb(255, 217, 119, 87))
        try {
            $graphics.FillEllipse($background, $left, $top, $diameter, $diameter)
        }
        finally {
            $background.Dispose()
        }

        $ringInset = [single]($diameter * 0.20)
        $ringDiameter = [single]($diameter - (2 * $ringInset))
        $ringWidth = [single][Math]::Max(1.5, $canvas * 0.052)
        $track = [System.Drawing.Pen]::new(
            [System.Drawing.Color]::FromArgb(80, 255, 255, 255),
            $ringWidth)
        $progress = [System.Drawing.Pen]::new(
            [System.Drawing.Color]::FromArgb(245, 255, 255, 255),
            $ringWidth)
        try {
            $track.StartCap = $track.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $progress.StartCap = $progress.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $ringLeft = [single]($left + $ringInset)
            $ringTop = [single]($top + $ringInset)
            $graphics.DrawEllipse($track, $ringLeft, $ringTop, $ringDiameter, $ringDiameter)
            $graphics.DrawArc($progress, $ringLeft, $ringTop, $ringDiameter, $ringDiameter, -90, 277)
        }
        finally {
            $track.Dispose()
            $progress.Dispose()
        }

        if ($canvas -ge 44) {
            $font = [System.Drawing.Font]::new(
                "Segoe UI",
                [single]($diameter * 0.28),
                [System.Drawing.FontStyle]::Bold,
                [System.Drawing.GraphicsUnit]::Pixel)
            $brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
            $format = [System.Drawing.StringFormat]::new()
            try {
                $format.Alignment = [System.Drawing.StringAlignment]::Center
                $format.LineAlignment = [System.Drawing.StringAlignment]::Center
                $bounds = [System.Drawing.RectangleF]::new($left, $top, $diameter, $diameter)
                $graphics.DrawString("C", $font, $brush, $bounds, $format)
            }
            finally {
                $format.Dispose()
                $brush.Dispose()
                $font.Dispose()
            }
        }

        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$assets = @(
    @{ Name = "StoreLogo.png"; Width = 50; Height = 50 },
    @{ Name = "Square44x44Logo.png"; Width = 44; Height = 44 },
    @{ Name = "Square150x150Logo.png"; Width = 150; Height = 150 },
    @{ Name = "Wide310x150Logo.png"; Width = 310; Height = 150 }
)

foreach ($asset in $assets) {
    New-ClaudeUsageLogo `
        -Width $asset.Width `
        -Height $asset.Height `
        -Path (Join-Path $outputPath $asset.Name)
}

$assets | ForEach-Object { Join-Path $outputPath $_.Name }
