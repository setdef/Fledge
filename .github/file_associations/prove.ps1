# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Experiment only (experiment/file-associations). The Windows half of
# prove.sh: on a runner that never ran fledge build, with no Ruby on PATH,
# no Fledge runtime anywhere, and a hostile Ruby environment, unpacks the
# builder app, built with build_tools: true, with Expand-Archive into a
# folder whose name has spaces and characters outside ASCII, has it run
# its own fledge build --from on a copy of a windowed game, with the
# launchers, rcedit, and NSIS it carries, and runs the app, then
# installs it with the setup program it wrote, runs it from there, and
# uninstalls it.
param(
  [Parameter(Mandatory)] [string] $Platform,
  [Parameter(Mandatory)] [string] $Archive,
  [Parameter(Mandatory)] [string] $Game
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$work = Join-Path $env:RUNNER_TEMP 'file-associations proof'
$place = Join-Path $work 'Mein Ort\Prüfung 日本'
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $work
New-Item -ItemType Directory -Force $place | Out-Null
Expand-Archive -LiteralPath $Archive -DestinationPath $place
Copy-Item -Recurse $Game (Join-Path $place 'Mein Spiel')
Set-Location $place
$env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
$env:RUBYOPT = '-rbogus'; $env:RUBYLIB = 'C:\nope'; $env:GEM_HOME = 'C:\nope'; $env:GEM_PATH = 'C:\nope'
$env:XDG_CACHE_HOME = Join-Path $work 'cache'
Remove-Item Env:FLEDGE_RUNTIME_DIR -ErrorAction SilentlyContinue
if (Get-Command ruby -ErrorAction SilentlyContinue) { throw 'ruby is reachable' }
$builder = ".\Builder-$Platform"
$tools = Join-Path $builder 'tools'
$size = (Get-ChildItem -Recurse -File $tools | Measure-Object -Sum Length).Sum
$whole = (Get-ChildItem -Recurse -File $builder | Measure-Object -Sum Length).Sum
Write-Host "== the builder's tools folder: $([math]::Round($size / 1KB)) KB of $([math]::Round($whole / 1KB)) KB"
Get-ChildItem $tools | Format-Table Name, Length

Write-Host '== fledge build --from, run by the builder app, inside itself, with no runtime at hand'
& "$builder\Builder.exe" 'Mein Spiel' 'Ausgabe'
if ($LASTEXITCODE -ne 0) { throw "fledge build --from exited $LASTEXITCODE" }
Get-ChildItem Ausgabe | Format-Table Name, Length
if (Test-Path "Ausgabe\Spiel-$Platform\tools") { throw "the builder's tools came along" }

Write-Host '== the app it wrote, unpacked with Expand-Archive and run with a path, as an opened file gives one'
Expand-Archive -LiteralPath "Ausgabe\Spiel-$Platform.zip" -DestinationPath 'Entpackt'
$spiel = ".\Entpackt\Spiel-$Platform\Spiel.exe"
$info = (Get-Item $spiel).VersionInfo
$info | Format-List FileDescription, ProductName, CompanyName, ProductVersion, OriginalFilename, Comments
if ($info.Comments -ne 'Ein Spiel aus einem Ordner') { throw "the program's Comments are '$($info.Comments)', not the game's description" }
if ($info.ProductName -ne 'Spiel' -or $info.CompanyName -ne 'Spielwerk' -or $info.OriginalFilename -ne 'Spiel.exe') { throw 'the version information is not the game''s' }
$report = Join-Path $work 'report.txt'
Start-Process -FilePath $spiel -ArgumentList "`"$report`"" -Wait
$out = (Get-Content -LiteralPath $report -Raw).Trim()
Write-Host $out
if ($out -ne 'Spiel says hello from app: an asset beside the game') { throw "unexpected report: $out" }

Write-Host '== its setup program, installed silently, the app run from where it went, and uninstalled'
$setup = Start-Process -FilePath "Ausgabe\Spiel-$Platform-setup.exe" -ArgumentList '/S' -Wait -PassThru
if ($setup.ExitCode -ne 0) { throw "the setup program exited $($setup.ExitCode)" }
$installed = Join-Path $env:LOCALAPPDATA 'Programs\Spiel'
$verb = 'HKCU:\Software\Classes\Directory\shell\com.example.Spiel\command'
Write-Host "the folders' verb: $((Get-Item -LiteralPath $verb).GetValue(''))"
$progids = (Get-Item -LiteralPath 'HKCU:\Software\Classes\.spiellevel\OpenWithProgids').GetValueNames() -join ','
if ($progids -ne 'com.example.Spiel.2') { throw ".spiellevel's OpenWithProgids is '$progids'" }
$uninstallKey = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\com.example.Spiel'
if ($uninstallKey.URLInfoAbout -ne 'https://example.com/spiel') { throw "URLInfoAbout is '$($uninstallKey.URLInfoAbout)'" }
Write-Host "ok: .spiellevel lists $progids, and the uninstall key's URLInfoAbout is $($uninstallKey.URLInfoAbout)"
Remove-Item -LiteralPath $report
Start-Process -FilePath (Join-Path $installed 'Spiel.exe') -ArgumentList "`"$report`"" -Wait
$out = (Get-Content -LiteralPath $report -Raw).Trim()
if ($out -ne 'Spiel says hello from app: an asset beside the game') { throw "unexpected report from the installed app: $out" }
Write-Host "ok: the installed app ran: $out"
$uninstall = Start-Process -FilePath (Join-Path $installed 'uninstall.exe') -ArgumentList '/S' -Wait -PassThru
if ($uninstall.ExitCode -ne 0) { throw "the uninstaller exited $($uninstall.ExitCode)" }
Write-Host "proved on $Platform"
