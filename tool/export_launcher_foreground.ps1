# Export the already extracted bottle for each platform without redrawing it.
# Harmony AppGallery requires 1024px layers with no additional inset or corner mask.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'assets/img/app_icon_foreground.png'
$harmonyPath = Join-Path $projectRoot 'ohos/AppScope/resources/base/media/app_icon_foreground.png'
$backgroundSourcePath = Join-Path $projectRoot 'assets/img/app_icon_background.svg'
$harmonyBackgroundPath = Join-Path $projectRoot 'ohos/AppScope/resources/base/media/app_icon_background.svg'
$androidPath = Join-Path $projectRoot 'android/app/src/main/res/drawable-nodpi/ic_launcher_bottle.png'
$source = [Drawing.Bitmap]::new($sourcePath)
$output = $null
$graphics = $null
try {
    if ($source.Width -ne $source.Height -or $source.GetPixel(0, 0).A -ne 0) {
        throw 'Expected a square foreground image with a transparent background.'
    }
    $output = [Drawing.Bitmap]::new(1024, 1024, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($output)
    $graphics.Clear([Drawing.Color]::Transparent)
    $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.DrawImage($source, [Drawing.Rectangle]::new(0, 0, 1024, 1024))
    $output.Save($harmonyPath, [Drawing.Imaging.ImageFormat]::Png)
    Copy-Item -LiteralPath $backgroundSourcePath -Destination $harmonyBackgroundPath -Force
    Copy-Item -LiteralPath $sourcePath -Destination $androidPath -Force
    Write-Output 'Exported Harmony 1024px foreground and background, and Android source copy.'
} finally {
    if ($graphics) { $graphics.Dispose() }
    if ($output) { $output.Dispose() }
    $source.Dispose()
}
