$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path (Split-Path $project -Parent) ('..\_work\tests\digestion-'+[Guid]::NewGuid().ToString('N'))
$foodRoot=Join-Path $fixture '饭盆'
$gut=Join-Path $fixture '猫的胃袋'
$cache=Join-Path $fixture 'cache'
$sources=Join-Path $fixture 'sources'
New-Item -ItemType Directory -Path $foodRoot,$cache,$sources | Out-Null
$script:checks=0
function Check($ok,$message) {if(-not $ok){throw $message}; $script:checks++}
function Job($data) {
    $data.root=$foodRoot; $data.cache=$cache; $data.stomach_capacity=1MB; $data.digestion_hours=1
    $key=[Guid]::NewGuid().ToString('N'); $request=Join-Path $cache ($key+'.json'); $reply=$request+'.reply'
    $data|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $request -Encoding utf8
    $worker=Start-Process -FilePath (Join-Path $project 'native\BowlFiles.exe') -ArgumentList @(('"'+$request+'"'),('"'+$reply+'"')) -WindowStyle Hidden -PassThru
    if(-not $worker.WaitForExit(15000)){throw 'native timeout'}
    Get-Content -LiteralPath $reply -Raw|ConvertFrom-Json
}
function AddFood($name,$size,$age) {
    $path=Join-Path $sources $name
    [IO.File]::WriteAllBytes($path,(New-Object byte[] $size))
    [IO.File]::SetCreationTimeUtc($path,[DateTime]::UtcNow.AddDays(-$age))
    [IO.File]::SetLastWriteTimeUtc($path,[DateTime]::UtcNow.AddSeconds(-10))
    $r=Job @{action='import';paths=@($path)}
    Check ($r.ok -and $r.accepted.Count -eq 1) 'import failed'
    $r.accepted[0]
}
function AgeGut($path,$hours) {
    $ledger=Join-Path $gut '.stomach-state.json'
    $data=Get-Content -LiteralPath $ledger -Raw|ConvertFrom-Json
    $key=[IO.Path]::GetFileName($path)
    $data.$key.entered=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()-[long]($hours*3600000)
    [IO.File]::SetAttributes($ledger,[IO.FileAttributes]::Normal)
    [IO.File]::WriteAllText($ledger,($data|ConvertTo-Json -Depth 8))
}
$r=Job @{action='ensure';art=(Join-Path $project 'assets\bowl\cauldron.png')}
Check ($r.ok -and (Test-Path -LiteralPath $gut)) 'stomach not created'
$first=AddFood 'first.txt' 600000 1
$second=AddFood 'second.txt' 600000 100
$scan=Job @{action='scan'}
Check ($scan.entries[0].path -eq $first -and $scan.entries[1].path -eq $second) 'arrival FIFO used source creation time'
$lock=[IO.File]::Open($first,'Open','ReadWrite','None')
try {$busy=Job @{action='scan'}}finally{$lock.Dispose()}
Check ($busy.entries[0].path -eq $first -and -not $busy.entries[0].ready) 'locked oldest file skipped'
$r=Job @{action='swallow';path=$first;token=$scan.entries[0].token}
Check ($r.ok -and $r.stomach_bytes -eq 600000 -and (Test-Path -LiteralPath $r.target)) 'swallow failed'
$firstGut=$r.target
$r=Job @{action='swallow';path=$second;token=$scan.entries[1].token}
Check (-not $r.ok -and (Test-Path -LiteralPath $second)) 'capacity overfilled'
$scan=Job @{action='scan'}
Check ($scan.stomach_bytes -eq 600000 -and $scan.bytes -eq 600000) 'metadata counted as food'
AgeGut $firstGut 2
$lock=[IO.File]::Open($firstGut,'Open','ReadWrite','None')
try {$scan=Job @{action='scan'}}finally{$lock.Dispose()}
Check ((Test-Path -LiteralPath $firstGut) -and $scan.stomach_bytes -eq 600000) 'locked expired food lost or discounted'
$scan=Job @{action='scan'}
Check (-not (Test-Path -LiteralPath $firstGut) -and $scan.stomach_bytes -eq 0) 'elapsed real-time expiry failed across helper restart'
$entry=$scan.entries[0]
$r=Job @{action='swallow';path=$entry.path;token=$entry.token}; $secondGut=$r.target
Check $r.ok 'second swallow failed'
AgeGut $secondGut 2
[IO.File]::AppendAllText($secondGut,'user changed this file')
$scan=Job @{action='scan'}
Check ((Test-Path -LiteralPath $secondGut) -and $scan.stomach_bytes -gt 600000) 'modified file deleted with stale timestamp'
AgeGut $secondGut 2
$scan=Job @{action='scan'}
Check (-not (Test-Path -LiteralPath $secondGut)) 'fresh file clock did not expire'
$manual=Join-Path $gut 'manual.txt'
[IO.File]::WriteAllText($manual,'manual'); [IO.File]::SetCreationTimeUtc($manual,[DateTime]::UtcNow.AddYears(-5))
[IO.File]::SetLastWriteTimeUtc($manual,[DateTime]::UtcNow.AddYears(-5))
$scan=Job @{action='scan'}
Check ((Test-Path -LiteralPath $manual) -and $scan.stomach_bytes -eq 6) 'manual file inherited old disk timestamp'
$duplicate=AddFood 'manual.txt' 8 1
$scan=Job @{action='scan'}; $entry=$scan.entries[0]
$r=Job @{action='swallow';path=$entry.path;token=$entry.token}
Check ($r.ok -and $r.target -ne $manual -and [IO.File]::ReadAllText($manual) -eq 'manual') 'stomach name collision overwrote file'
$ledger=Join-Path $gut '.stomach-state.json'; $saved=[IO.File]::ReadAllText($ledger)
[IO.File]::SetAttributes($ledger,[IO.FileAttributes]::Normal)
[IO.File]::WriteAllText($ledger,'{corrupt')
$scan=Job @{action='scan'}
Check (-not $scan.ok -and (Test-Path -LiteralPath $manual)) 'corrupt ledger caused deletion'
[IO.File]::WriteAllText($ledger,$saved)
Write-Output "DIGESTION: $script:checks checks passed; $fixture"
