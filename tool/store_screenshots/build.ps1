param(
    [string]$Flutter = 'flutter',
    [string]$OutputDirectory = 'build/store-assets-1.1.0-6/app',
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
    # A browser reload can reuse strongly cached scripts even on localhost.
    # Version both generated script URLs; production web sources stay untouched.
    $captureOutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
    $captureBuildHash = (Get-FileHash -LiteralPath (Join-Path $captureOutputDirectory 'main.dart.js') -Algorithm SHA256).Hash.Substring(0, 12).ToLowerInvariant()
    $captureBootstrapPath = Join-Path $captureOutputDirectory 'flutter_bootstrap.js'
    $captureIndexPath = Join-Path $captureOutputDirectory 'index.html'
    $captureBootstrap = [System.IO.File]::ReadAllText($captureBootstrapPath)
    $captureIndex = [System.IO.File]::ReadAllText($captureIndexPath)
    $captureMainPattern = '"mainJsPath":"main\.dart\.js(?:\?v=[a-f0-9]{12})?"'
    $captureBootstrapPattern = 'src="flutter_bootstrap\.js(?:\?v=[a-f0-9]{12})?"'
    if ([regex]::Matches($captureBootstrap, $captureMainPattern).Count -ne 1 -or
        [regex]::Matches($captureIndex, $captureBootstrapPattern).Count -ne 1) {
        throw 'Generated Flutter script URLs changed; capture cache busting must be updated.'
    }
    $captureBootstrap = [regex]::Replace($captureBootstrap, $captureMainPattern, ('"mainJsPath":"main.dart.js?v=' + $captureBuildHash + '"'))
    $captureIndex = [regex]::Replace($captureIndex, $captureBootstrapPattern, ('src="flutter_bootstrap.js?v=' + $captureBuildHash + '"'))
    $captureUtf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($captureBootstrapPath, $captureBootstrap, $captureUtf8)
    [System.IO.File]::WriteAllText($captureIndexPath, $captureIndex, $captureUtf8)
    Write-Output "Built capture site: $OutputDirectory"
    Write-Output 'Serve on localhost only; Windows fonts in this build are for local rendering, not redistribution.'
} finally {
    Pop-Location
}
