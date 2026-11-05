# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Experiment only (experiment/build-from). The Windows half of prove.sh:
# on a runner that never ran fledge build, with no Ruby on PATH and a
# hostile Ruby environment, unpacks the builder app with Expand-Archive
# into a folder whose name has spaces and characters outside ASCII, has
# it run its own fledge build --from on a copy of the game, first with no
# runtime at hand, which must fail and say where to put one, then with
# FLEDGE_RUNTIME_DIR, and runs the app that comes out.
param(
  [Parameter(Mandatory)] [string] $Platform,
  [Parameter(Mandatory)] [string] $Archive,
  [Parameter(Mandatory)] [string] $Game,
  [Parameter(Mandatory)] [string] $Runtimes
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$work = Join-Path $env:RUNNER_TEMP 'build-from proof'
$place = Join-Path $work 'Mein Ort\Prüfung 日本'
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $work
New-Item -ItemType Directory -Force $place | Out-Null
Expand-Archive -LiteralPath $Archive -DestinationPath $place
Copy-Item -Recurse $Game (Join-Path $place 'Mein Spiel')
Set-Location $place
$env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
$env:RUBYOPT = '-rbogus'; $env:RUBYLIB = 'C:\nope'; $env:GEM_HOME = 'C:\nope'; $env:GEM_PATH = 'C:\nope'
$env:XDG_CACHE_HOME = Join-Path $work 'cache'
if (Get-Command ruby -ErrorAction SilentlyContinue) { throw 'ruby is reachable' }
$builder = ".\Builder-$Platform\Builder.exe"

Write-Host '== fledge build --from with no runtime at hand: it must fail and say where to put one'
& $builder 'Mein Spiel' 'Ohne' 2>&1 | Tee-Object -Variable refused | Write-Host
if ($LASTEXITCODE -ne 1) { throw "expected exit 1, got $LASTEXITCODE" }
if (-not ($refused -match 'FLEDGE_RUNTIME_DIR')) { throw 'the refusal does not name FLEDGE_RUNTIME_DIR' }

Write-Host '== fledge build --from, with the runtime in FLEDGE_RUNTIME_DIR'
$env:FLEDGE_RUNTIME_DIR = $Runtimes
& $builder 'Mein Spiel' 'Ausgabe'
if ($LASTEXITCODE -ne 0) { throw "fledge build --from exited $LASTEXITCODE" }
Remove-Item Env:FLEDGE_RUNTIME_DIR
Get-ChildItem Ausgabe | Format-Table Name, Length
Get-Content "Ausgabe\Spiel-$Platform\fledge.cfg" -TotalCount 3
if (Test-Path "Ausgabe\Spiel-$Platform\Builder.exe") { throw "the builder's program came along" }

Write-Host '== the app it wrote, unpacked with Expand-Archive and run'
Expand-Archive -LiteralPath "Ausgabe\Spiel-$Platform.zip" -DestinationPath 'Entpackt'
$spiel = ".\Entpackt\Spiel-$Platform\Spiel.exe"
$info = (Get-Item $spiel).VersionInfo
$info | Format-List FileDescription, ProductName, CompanyName, ProductVersion, OriginalFilename
if ($info.ProductName -ne 'Spiel' -or $info.CompanyName -ne 'Spielwerk' -or $info.OriginalFilename -ne 'Spiel.exe') { throw 'the version information is not the game''s' }
$out = (& $spiel) -join "`n"
Write-Host $out
if ($LASTEXITCODE -ne 0) { throw "Spiel.exe exited $LASTEXITCODE" }
$expected = "Spiel says hello from app: an asset beside the game`nRUBYOPT=-rbundler/setup -rbogus"
if ($out -ne $expected) { throw "expected: $expected" }
Write-Host "proved on $Platform"
