param([switch]$Editor, [string]$GodotPath)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $GodotPath) {
    $GodotPath = Join-Path (Split-Path (Split-Path $projectRoot -Parent) -Parent) '_tools\runtime\godot-build\godot\Godot_v4.7.2-stable_win64.exe'
}
if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw 'Godot executable not found. Supply -GodotPath with your Godot 4.3+ executable.'
}
$launchArgs = @('--path', "`"$projectRoot`"")
if ($Editor) { $launchArgs += '--editor' }
else { $launchArgs += @('--','--dev') }
# The editor/pet is the user-facing interactive application, not a background helper.
Start-Process -FilePath $GodotPath -ArgumentList $launchArgs -WindowStyle Normal
