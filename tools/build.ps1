param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$game = Join-Path $root 'Game'
$engine = Join-Path $root '_tools/runtime/godot-build/godot/Godot_v4.7.2-stable_win64_console.exe'
$output = Join-Path $root '_work/release'
if (-not (Test-Path -LiteralPath $engine)) { throw 'Run tools/setup.py first. See docs/BUILD.md.' }
New-Item -ItemType Directory -Force -Path $output | Out-Null
& $Python (Join-Path $game 'tools/manage.py') sync
if ($LASTEXITCODE -ne 0) { throw 'Asset sync failed' }
& (Join-Path $game 'Godot/tools/build-bowl-helper.ps1')
& (Join-Path $game 'Godot/tools/build-desktop-shell.ps1')
& (Join-Path $game 'Godot/tools/build-plugin.ps1') -Target both -Python $Python
& $engine --headless --path (Join-Path $game 'Godot') --editor --import
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
& $engine --headless --path (Join-Path $game 'Godot') --export-release 'Windows Desktop' (Join-Path $output 'DolikePet.exe')
if ($LASTEXITCODE -ne 0) { throw 'Godot export failed' }
Copy-Item -LiteralPath (Join-Path $game 'Godot/licenses') -Destination $output -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination $output -Force
Copy-Item -LiteralPath (Join-Path $root 'THIRD_PARTY_NOTICES.md') -Destination $output -Force
Copy-Item -LiteralPath (Join-Path $root 'ASSET_LICENSES.md') -Destination $output -Force
Copy-Item -Path (Join-Path $root 'LICENSES/*') -Destination (Join-Path $output 'licenses') -Force
Write-Output "Built: $output"
