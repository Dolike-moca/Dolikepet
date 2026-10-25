$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$outputFile = Join-Path $projectRoot 'native\BowlFiles.exe'
$sourceFile = Join-Path $projectRoot 'native\BowlFiles.cs'
$digestionFile = Join-Path $projectRoot 'native\BowlDigestion.cs'
& $compiler /nologo /target:winexe /optimize+ /reference:System.Drawing.dll /reference:System.Web.Extensions.dll "/out:$outputFile" $sourceFile $digestionFile
if ($LASTEXITCODE -ne 0) { throw 'Bowl helper build failed' }
