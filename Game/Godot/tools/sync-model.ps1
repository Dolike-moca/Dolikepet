param([string]$Python = "python")
$ErrorActionPreference='Stop'
$game=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
& $Python (Join-Path $game 'tools\manage.py') sync
if($LASTEXITCODE -ne 0){throw 'Asset/model synchronization failed'}
