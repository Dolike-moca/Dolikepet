$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$outputFile = Join-Path $projectRoot 'native\DesktopShell.exe'
$sourceFile = Join-Path $projectRoot 'native\DesktopShell.cs'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ "/out:$outputFile" $sourceFile
if ($LASTEXITCODE -ne 0) { throw 'Desktop shell helper build failed' }
