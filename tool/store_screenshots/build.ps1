param(
    [string]$Flutter = 'flutter',
    [string]$OutputDirectory = 'build/store-assets-1.1.0-5/app',
    [string]$FontDirectory = (Join-Path $env:WINDIR 'Fonts')
)
$ErrorActionPreference = 'Stop'
$repoDirectory = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
foreach ($fontName in @('msyh.ttc', 'msyhbd.ttc')) {
    if (-not (Test-Path -LiteralPath (Join-Path $FontDirectory $fontName))) {
        throw "Microsoft YaHei is required: $fontName"
    }
}
Push-Location $repoDirectory
try {
    & $Flutter build web --no-pub --release --pwa-strategy=none `
        --target tool/store_screenshots/demo_main.dart --output $OutputDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Store screenshot build failed.' }
    $captureFontDirectory = Join-Path $OutputDirectory 'assets/capture-fonts'
    New-Item -ItemType Directory -Force -Path $captureFontDirectory | Out-Null
    foreach ($fontName in @('msyh.ttc', 'msyhbd.ttc')) {
        Copy-Item -LiteralPath (Join-Path $FontDirectory $fontName) -Destination (Join-Path $captureFontDirectory $fontName) -Force
    }
    Write-Output "Built capture site: $OutputDirectory"
    Write-Output 'Serve on localhost only; Windows fonts in this build are for local rendering, not redistribution.'
} finally {
    Pop-Location
}
