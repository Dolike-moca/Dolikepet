param([string]$Destination, [string]$ManifestPath)
$ErrorActionPreference = 'Stop'
$game = Split-Path $PSScriptRoot -Parent
$project = Split-Path $game -Parent
if ([string]::IsNullOrWhiteSpace($Destination)) {
    $Destination = Join-Path (Split-Path $project -Parent) 'Dolikepet'
}
$Destination = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $Destination) { throw "Destination already exists; choose a new folder: $Destination" }
$runtime = Join-Path $game 'Runtime'
$manifest = @(Get-Content -LiteralPath (Join-Path $runtime 'release-manifest.json') -Raw | ConvertFrom-Json)
$packHash = ''
$names = @('DolikePet.exe','DolikePet.pck','libgd_cubism.windows.release.x86_64.dll')
foreach ($name in $names) {
    $record = @($manifest | Where-Object { $_.file -eq $name })
    $hash = (Get-FileHash -LiteralPath (Join-Path $runtime $name) -Algorithm SHA256).Hash
    if ($record.Count -ne 1 -or $record[0].Hash -ne $hash) { throw "Formal release checksum mismatch: $name" }
    if ($name -eq 'DolikePet.pck') { $packHash = $hash.ToLowerInvariant() }
}
New-Item -ItemType Directory -Path $Destination | Out-Null
foreach ($name in $names) {
    Copy-Item -LiteralPath (Join-Path $runtime $name) -Destination (Join-Path $Destination $name)
}
$licenses = Join-Path $Destination 'licenses'
New-Item -ItemType Directory -Path $licenses | Out-Null
Get-ChildItem -LiteralPath (Join-Path $game 'Godot/licenses') -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $licenses $_.Name)
}
Copy-Item -LiteralPath (Join-Path $project 'LICENSE') -Destination (Join-Path $licenses 'Dolikepet-MIT.txt')
Copy-Item -LiteralPath (Join-Path $project 'LICENSES/CC-BY-4.0.txt') -Destination $licenses
foreach ($notice in @('ASSET_LICENSES.md','THIRD_PARTY_NOTICES.md')) {
    Copy-Item -LiteralPath (Join-Path $project $notice) -Destination $licenses
}
$readme = Get-Content -LiteralPath (Join-Path $game 'docs/public/游玩说明.txt') -Raw -Encoding utf8
[IO.File]::WriteAllText((Join-Path $Destination '游玩说明.txt'),$readme,[Text.UTF8Encoding]::new($true))
$files = @(Get-ChildItem -LiteralPath $Destination -Recurse -File | ForEach-Object {
    @{file=[IO.Path]::GetRelativePath($Destination,$_.FullName);bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}
})
$report = @{destination=$Destination;runtimeSha256=$packHash;files=$files;totalBytes=($files | Measure-Object -Property bytes -Sum).Sum}
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath = Join-Path $project '_work/playable-package.json' }
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ManifestPath -Encoding utf8
Write-Output ("Playable folder: {0}; {1:N2} MiB; {2} files" -f $Destination,($report.totalBytes/1MB),$files.Count)
