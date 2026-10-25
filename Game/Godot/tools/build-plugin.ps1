param(
    [ValidateSet('debug','release','both')][string]$Target = 'both',
    [string]$Python = "python"
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$gameRoot = Split-Path $projectRoot -Parent
$buildRoot = Join-Path (Split-Path $gameRoot -Parent) '_tools\runtime\godot-build'
$sourceRoot = Join-Path $buildRoot 'gd_cubism'
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'godot-cpp\SConstruct'))) {
    throw 'Missing pinned source dependencies. See README.md for setup.'
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'thirdparty\CubismSdkForNative-5-r.5\Core'))) {
    throw 'Extract the licensed CubismSdkForNative-5-r.5 ZIP into gd_cubism/thirdparty first.'
}
& $Python (Join-Path $PSScriptRoot 'patch-gdcubism.py') $sourceRoot
if ($LASTEXITCODE -ne 0) { throw 'Compatibility patch failed.' }
$previousPythonPath = $env:PYTHONPATH
$env:PYTHONPATH = Join-Path $buildRoot 'python'
$targets = if ($Target -eq 'both') { @('debug','release') } else { @($Target) }
Push-Location $sourceRoot
try {
    foreach ($kind in $targets) {
        $buildTarget = if ($kind -eq 'debug') { 'template_debug' } else { 'template_release' }
        & $Python -m SCons platform=windows arch=x86_64 "target=$buildTarget" -j6
        if ($LASTEXITCODE -ne 0) { throw "Native plugin $kind build failed." }
        $dest = Join-Path $projectRoot 'addons\gd_cubism\bin'
        New-Item -ItemType Directory -Force $dest | Out-Null
        Copy-Item -LiteralPath "demo/addons/gd_cubism/bin/libgd_cubism.windows.$kind.x86_64.dll" -Destination $dest
    }
} finally {
    Pop-Location
    $env:PYTHONPATH = $previousPythonPath
}
Write-Output 'Godot Live2D plugin built and copied into the project.'
