# Export the already extracted bottle for each platform without redrawing it.
# Harmony's 288px layered foreground contains a centered 192px image canvas.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'assets/img/app_icon_foreground.png'
$harmonyPath = Join-Path $projectRoot 'ohos/AppScope/resources/base/media/app_icon_foreground.png'
$androidPath = Join-Path $projectRoot 'android/app/src/main/res/drawable-nodpi/ic_launcher_bottle.png'
$source = [Drawing.Bitmap]::new($sourcePath)
$output = $null
$graphics = $null
try {
    if ($source.Width -ne $source.Height -or $source.GetPixel(0, 0).A -ne 0) {
        throw 'Expected a square foreground image with a transparent background.'
    }
    $output = [Drawing.Bitmap]::new(288, 288, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($output)
    $graphics.Clear([Drawing.Color]::Transparent)
    $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.DrawImage($source, [Drawing.Rectangle]::new(48, 48, 192, 192))
    $output.Save($harmonyPath, [Drawing.Imaging.ImageFormat]::Png)
    Copy-Item -LiteralPath $sourcePath -Destination $androidPath -Force
    Write-Output 'Exported Harmony 288px foreground and Android source copy.'
} finally {
    if ($graphics) { $graphics.Dispose() }
    if ($output) { $output.Dispose() }
    $source.Dispose()
}
