$ErrorActionPreference='Stop'
$godotRoot=Split-Path $PSScriptRoot -Parent
$projectRoot=Split-Path (Split-Path $godotRoot -Parent) -Parent
$fixture=Join-Path $projectRoot '_work\tests\desktop-shell'
New-Item -ItemType Directory -Force -Path $fixture | Out-Null
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$exe=Join-Path $fixture 'DesktopShellTests.exe'
& $compiler /nologo /target:exe /platform:x64 /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /main:DesktopShellTests "/out:$exe" (Join-Path $godotRoot 'native\DesktopShell.cs') (Join-Path $PSScriptRoot 'DesktopShellTests.cs')
if($LASTEXITCODE -ne 0){throw 'Native shell fixture compile failed'}
& $exe
if($LASTEXITCODE -ne 0){throw 'Native shell fixture failed'}
