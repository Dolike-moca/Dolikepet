$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path (Split-Path $project -Parent) ('..\_work\tests\bowl-native-' + [Guid]::NewGuid().ToString('N'))
$foodRoot = Join-Path $fixture '饭盆'
$cache = Join-Path $fixture 'cache'
$source = Join-Path $fixture '来源'
New-Item -ItemType Directory -Path $foodRoot,$cache,$source | Out-Null
$helper = Join-Path $project 'native\BowlFiles.exe'
$script:checks = 0
function Check($condition, $label) { if (-not $condition) { throw $label }; $script:checks++ }
function Job($data) {
    $data.root = $foodRoot; $data.cache = $cache
    $key = [Guid]::NewGuid().ToString('N')
    $request = Join-Path $cache ($key+'.json'); $reply = Join-Path $cache ($key+'.reply.json')
    $data | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $request -Encoding utf8
    $process = Start-Process -FilePath $helper -ArgumentList @(('"'+$request+'"'),('"'+$reply+'"')) -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(15000)) { throw 'worker timed out' }
    return Get-Content -LiteralPath $reply -Raw | ConvertFrom-Json
}
$result = Job @{action='ensure'; art=(Join-Path $project 'assets\bowl\cauldron.png')}
Check $result.ok 'ensure failed'
Check (Test-Path -LiteralPath (Join-Path $foodRoot 'desktop.ini')) 'folder icon metadata missing'
$a = Join-Path $source '可爱 的文档.txt'
[IO.File]::WriteAllText($a,'test food alpha')
[IO.File]::SetLastWriteTimeUtc($a,[DateTime]::UtcNow.AddSeconds(-10))
$result = Job @{action='import'; paths=@($a)}
Check ($result.ok -and $result.accepted.Count -eq 1) ('import failed: '+($result|ConvertTo-Json -Depth 6))
Check (-not (Test-Path -LiteralPath $a)) 'source was not moved'
$first = $result.accepted[0]
[IO.File]::WriteAllText($a,'test food beta')
[IO.File]::SetLastWriteTimeUtc($a,[DateTime]::UtcNow.AddSeconds(-10))
$result = Job @{action='import'; paths=@($a)}
Check ($result.accepted.Count -eq 1 -and $result.accepted[0] -ne $first) 'collision overwrote food'
$scan = Job @{action='scan'}
Check ($scan.ok -and $scan.entries.Count -eq 2) 'scan entries incorrect'
Check ($scan.bytes -eq 29) ('byte total includes metadata or is wrong: '+$scan.bytes)
Check (Test-Path -LiteralPath $scan.entries[0].icon) 'Windows icon missing'
Add-Type -AssemblyName System.Drawing
$imageCheck = [Drawing.Bitmap]::FromFile($scan.entries[0].icon)
try { Check ($imageCheck.GetPixel(0,0).A -eq 0) 'Windows icon lost transparency' } finally { $imageCheck.Dispose() }
$entry = $scan.entries[0]
[IO.File]::AppendAllText($entry.path,' changed')
$result = Job @{action='swallow'; path=$entry.path; token=$entry.token}
Check (-not $result.ok -and (Test-Path -LiteralPath $entry.path)) 'changed file was deleted'
$outside = Join-Path $source 'outside.txt'
[IO.File]::WriteAllText($outside,'must remain')
$result = Job @{action='swallow'; path=$outside; token='invalid'}
Check (-not $result.ok -and (Test-Path -LiteralPath $outside)) 'root escape permitted'
$entry = $scan.entries[1]
$lock = [IO.File]::Open($entry.path,'Open','ReadWrite','None')
try { $result = Job @{action='swallow'; path=$entry.path; token=$entry.token} } finally { $lock.Dispose() }
Check (-not $result.ok -and (Test-Path -LiteralPath $entry.path)) 'locked file lost'
$result = Job @{action='swallow'; path=$entry.path; token=$entry.token}
Check ($result.ok -and -not (Test-Path -LiteralPath $entry.path)) ('swallow failed: '+($result|ConvertTo-Json))
Check (Test-Path -LiteralPath $result.target) 'swallowed file missing from stomach'
Write-Output "BOWL FILES: $script:checks checks passed. Fixture: $fixture"

