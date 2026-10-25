param(
    [string]$Python="python",
    [switch]$SkipPsd,
    [switch]$Publish
)
$ErrorActionPreference='Stop'
$game=Split-Path $PSScriptRoot -Parent
$project=Split-Path $game -Parent
$godot=Join-Path $project '_tools\runtime\godot-build\godot\Godot_v4.7.2-stable_win64_console.exe'
$staging=Join-Path $project '_work\release'
New-Item -ItemType Directory -Force -Path $staging|Out-Null
if(-not $Publish){
& $Python (Join-Path $PSScriptRoot 'manage.py') sync
if($LASTEXITCODE -ne 0){throw 'Asset check failed'}
if(-not $SkipPsd){
    & $Python (Join-Path $PSScriptRoot 'manage.py') psd
    if($LASTEXITCODE -ne 0){throw 'PSD generation failed'}
}
& (Join-Path $game 'Godot\tools\build-bowl-helper.ps1')
& (Join-Path $game 'Godot\tools\build-desktop-shell.ps1')
& (Join-Path $game 'Godot\tools\build-plugin.ps1') -Target both -Python $Python
& $godot --headless --path (Join-Path $game 'Godot') --editor --import
if($LASTEXITCODE -ne 0){throw 'Godot import failed'}
& $godot --headless --path (Join-Path $game 'Godot') --export-release 'Windows Desktop' (Join-Path $staging 'DolikePet.exe')
if($LASTEXITCODE -ne 0){throw 'Godot export failed'}
}
$runtime=Join-Path $game 'Runtime'
# Stage first; the user-facing release must be closed before replacing locked files.
foreach($name in @('DolikePet.exe','DolikePet.pck','libgd_cubism.windows.release.x86_64.dll')) {
    $file=Join-Path $staging $name
    if(-not (Test-Path -LiteralPath $file)){throw "Missing release output: $file"}
}
if(-not $Publish){Write-Output "Candidate ready for review: $staging"; return}
$auditPath=Join-Path $project '_work\final-review\visual-audit.json'
if(-not (Test-Path -LiteralPath $auditPath)){throw 'Visual audit required before publication'}
$audit=Get-Content -LiteralPath $auditPath -Raw|ConvertFrom-Json
$packHash=(Get-FileHash -LiteralPath (Join-Path $staging 'DolikePet.pck') -Algorithm SHA256).Hash.ToLowerInvariant()
if($audit.frames -ne 720 -or $audit.identicalFrames -ne 720 -or @($audit.changedFrames).Count -ne 0 -or $audit.candidateSha256 -ne $packHash){throw 'The current candidate has not passed the complete visual audit'}
foreach($group in @('logic','render','native')) {
    $result=Join-Path $project ("_work\tests\logs\$group-results.json")
    if(-not (Test-Path -LiteralPath $result)){throw "Missing $group regression results"}
    $checks=@(Get-Content -LiteralPath $result -Raw|ConvertFrom-Json)
    if($checks.Count -eq 0 -or @($checks|Where-Object {$_.exitCode -ne 0}).Count -gt 0){throw "Failed $group regressions"}
}
New-Item -ItemType Directory -Force -Path $runtime|Out-Null
foreach($name in @('DolikePet.exe','DolikePet.pck','libgd_cubism.windows.release.x86_64.dll')) {
    Copy-Item -LiteralPath (Join-Path $staging $name) -Destination (Join-Path $runtime $name) -Force
}
Get-ChildItem -LiteralPath $runtime -File | Where-Object {$_.Name -ne 'release-manifest.json'} | Get-FileHash -Algorithm SHA256 | Select-Object @{n='file';e={Split-Path $_.Path -Leaf}},Hash | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runtime 'release-manifest.json') -Encoding utf8
Write-Output "Release ready: $runtime"
