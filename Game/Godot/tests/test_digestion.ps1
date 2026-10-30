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

# Each case is confined to this run's generated fixture. Large logical sizes
# are enough to exercise the rule without copying a real user's file.
function NewCase($name) {
    $case=[IO.Path]::GetFullPath((Join-Path $fixture $name))
    $script:foodRoot=Join-Path $case '饭盆'
    $script:gut=Join-Path $case '猫的胃袋'
    $script:cache=Join-Path $case 'cache'
    New-Item -ItemType Directory -Force -Path $foodRoot,$gut,$cache | Out-Null
}
function RawFood($name,[long]$size,[int]$ageMinutes=5) {
    $path=Join-Path $foodRoot $name
    $stream=[IO.File]::Open($path,'CreateNew','ReadWrite','None')
    try {$stream.SetLength($size)}finally{$stream.Dispose()}
    [IO.File]::SetCreationTimeUtc($path,[DateTime]::UtcNow.AddMinutes(-$ageMinutes))
    [IO.File]::SetLastWriteTimeUtc($path,[DateTime]::UtcNow.AddSeconds(-10))
    return $path
}
function ResizeFixture($path,[long]$size) {
    $stream=[IO.File]::Open($path,'OpenOrCreate','ReadWrite','None')
    try {$stream.SetLength($size)}finally{$stream.Dispose()}
    [IO.File]::SetLastWriteTimeUtc($path,[DateTime]::UtcNow.AddSeconds(-10))
}

NewCase 'oversized-single'
$large=RawFood 'oldest.dat' 5MB 10
$next=RawFood 'newer.dat' 6MB 5
$scan=Job @{action='scan'}
Check ($scan.smallest_bytes -eq 5MB -and $scan.entries[0].path -eq $large) 'full queue minimum or FIFO is wrong'
$r=Job @{action='swallow';path=$large;token=$scan.entries[0].token}
Check ($r.ok -and $r.stomach_bytes -eq 5MB -and -not (Test-Path -LiteralPath $large) -and (Get-Item -LiteralPath $r.target).Length -eq 5MB) 'one oversized food did not move with its real size'
$largeGut=$r.target
$r=Job @{action='swallow';path=$next;token=$scan.entries[1].token}
Check (-not $r.ok -and (Test-Path -LiteralPath $next)) 'already overfull stomach accepted another oversized file'
$scan=Job @{action='scan'}
Check ($scan.stomach_bytes -eq 5MB -and $scan.smallest_bytes -eq 6MB) 'oversized usage was clamped instead of preserving actual bytes'
AgeGut $largeGut 2
$scan=Job @{action='scan'}
Check ($scan.stomach_bytes -eq 0 -and -not (Test-Path -LiteralPath $largeGut)) 'oversized file did not use its normal digestion timer'
$r=Job @{action='swallow';path=$next;token=$scan.entries[0].token}
Check ($r.ok -and $r.stomach_bytes -eq 6MB) 'oversized exception did not become available after digestion'

NewCase 'oversized-half-boundary'
$large=RawFood 'large.dat' 5MB
$existing=Join-Path $gut 'existing.dat'
ResizeFixture $existing 512KB
$scan=Job @{action='scan'}
$r=Job @{action='swallow';path=$large;token=$scan.entries[0].token}
Check (-not $r.ok -and (Test-Path -LiteralPath $large)) 'exactly half-full stomach accepted oversized food'
ResizeFixture $existing (512KB-1)
$scan=Job @{action='scan'}
$r=Job @{action='swallow';path=$large;token=$scan.entries[0].token}
Check ($r.ok -and $r.stomach_bytes -eq (5MB+512KB-1)) 'strictly below half did not admit exactly one oversized food'

NewCase 'oversized-mixed'
$large=RawFood 'oldest-large.dat' 5MB 10
$small=RawFood 'newer-small.dat' 64 5
$scan=Job @{action='scan'}
Check ($scan.smallest_bytes -eq 64) 'mixed queue minimum missed its smaller file'
$r=Job @{action='swallow';path=$large;token=$scan.entries[0].token;allow_oversized=$true}
Check (-not $r.ok -and (Test-Path -LiteralPath $large) -and (Test-Path -LiteralPath $small)) 'mixed queue or untrusted override bypassed capacity'
ResizeFixture $small 0
$scan=Job @{action='scan'}
Check ($scan.smallest_bytes -eq 0) 'zero-byte food was omitted from the all-oversized decision'

NewCase 'oversized-after-scan'
$large=RawFood 'oldest-large.dat' 5MB 10
$scan=Job @{action='scan'}; $originalToken=$scan.entries[0].token
Check ($scan.smallest_bytes -eq 5MB) 'single large scan did not advertise the exception'
$late=RawFood 'late-small.dat' 32 1
$r=Job @{action='swallow';path=$large;token=$originalToken}
Check (-not $r.ok -and (Test-Path -LiteralPath $large)) 'late-arriving small food was not rechecked at swallow'
ResizeFixture $late 6MB
$scan=Job @{action='scan'}
Check ($scan.smallest_bytes -eq 5MB) 'both oversized files were not recognized after refresh'
ResizeFixture $late 48
$r=Job @{action='swallow';path=$large;token=$originalToken}
Check (-not $r.ok -and (Test-Path -LiteralPath $large)) 'food shrunk since scan was not rechecked at swallow'

NewCase 'oversized-past-page'
for($i=0;$i -lt 128;$i++) {$null=RawFood ('large-{0:D3}.dat' -f $i) (1MB+1) (200-$i)}
$small=RawFood 'last-small.dat' 7 1
$scan=Job @{action='scan'}
Check ($scan.entries.Count -eq 128 -and @($scan.entries | Where-Object {$_.path -eq $small}).Count -eq 0 -and $scan.smallest_bytes -eq 7) 'queue page limit hid the full-directory minimum'
$entry=$scan.entries[0]
$r=Job @{action='swallow';path=$entry.path;token=$entry.token}
Check (-not $r.ok -and (Test-Path -LiteralPath $entry.path)) 'small food beyond the first 128 files allowed overflow'

NewCase 'oversized-unreadable'
$large=RawFood 'oldest-large.dat' 5MB 10
$other=RawFood 'locked-large.dat' 6MB 5
$scan=Job @{action='scan'}
$lock=[IO.File]::Open($other,'Open','ReadWrite','None')
try {$r=Job @{action='swallow';path=$large;token=$scan.entries[0].token}}finally{$lock.Dispose()}
Check (-not $r.ok -and (Test-Path -LiteralPath $large)) 'incomplete live verification permitted oversized swallow'

NewCase 'empty-minimum'
$scan=Job @{action='scan'}
Check ($scan.smallest_bytes -eq -1 -and $scan.entries.Count -eq 0) 'empty queue claimed a smallest food size'
Write-Output "DIGESTION: $script:checks checks passed; $fixture"
