# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# The Windows half of deliver-from.sh (ADR 032): on a runner that never
# ran fledge build, with no Ruby on PATH, no Fledge runtime anywhere, and
# a hostile Ruby environment, unpacks the builder app, built with
# build_tools: true and Fledge as a gem, with Expand-Archive into a folder
# whose name has spaces and characters outside ASCII, has it run its own
# fledge build --from on a copy of a windowed game with the launchers,
# rcedit, and NSIS it carries, reads the result's identity back, runs
# it, installs it with the setup program it wrote, runs it from there,
# and uninstalls it. Then it has the builder refuse what --from refuses,
# by exit status and message.
param(
  [Parameter(Mandatory)] [string] $Platform,
  [Parameter(Mandatory)] [string] $Archive,
  [Parameter(Mandatory)] [string] $Game
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$badAppStatus = [int] $env:FROM_REFUSES_A_BAD_APP_WITH
$work = Join-Path $env:RUNNER_TEMP 'from proof'
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
$expected = 'Spiel says hello from app: an asset beside the game'

Write-Host '== fledge build --from, run by the builder app, inside itself, with no runtime at hand'
& "$builder\Builder.exe" 'Mein Spiel' 'Ausgabe'
if ($LASTEXITCODE -ne 0) { throw "fledge build --from exited $LASTEXITCODE" }
Get-ChildItem Ausgabe | Format-Table Name, Length
if (Test-Path "Ausgabe\Spiel-$Platform\tools") { throw "the builder's tools came along" }

Write-Host '== the app it wrote, unpacked with Expand-Archive, its identity read back, and run with a path'
Expand-Archive -LiteralPath "Ausgabe\Spiel-$Platform.zip" -DestinationPath 'Entpackt'
$spiel = ".\Entpackt\Spiel-$Platform\Spiel.exe"
$info = (Get-Item $spiel).VersionInfo
$info | Format-List FileDescription, ProductName, CompanyName, ProductVersion, OriginalFilename, Comments
if ($info.Comments -ne 'Ein Spiel aus einem Ordner') { throw "the program's Comments are '$($info.Comments)', not the game's description" }
if ($info.ProductName -ne 'Spiel' -or $info.CompanyName -ne 'Spielwerk' -or $info.OriginalFilename -ne 'Spiel.exe') { throw 'the version information is not the game''s' }
$report = Join-Path $work 'report.txt'
Start-Process -FilePath $spiel -ArgumentList "`"$report`"" -Wait
$out = (Get-Content -LiteralPath $report -Raw).Trim()
if ($out -ne $expected) { throw "unexpected report: $out" }
Write-Host "ok: the app ran: $out"

Write-Host '== its setup program, installed silently, read back, the app run from where it went, and uninstalled'
$setup = Start-Process -FilePath "Ausgabe\Spiel-$Platform-setup.exe" -ArgumentList '/S' -Wait -PassThru
if ($setup.ExitCode -ne 0) { throw "the setup program exited $($setup.ExitCode)" }
$installed = Join-Path $env:LOCALAPPDATA 'Programs\Spiel'
$verb = (Get-Item -LiteralPath 'HKCU:\Software\Classes\Directory\shell\com.example.Spiel\command').GetValue('')
if ($verb -notlike '*Spiel.exe*') { throw "the folders' verb is '$verb'" }
$progids = (Get-Item -LiteralPath 'HKCU:\Software\Classes\.spiellevel\OpenWithProgids').GetValueNames() -join ','
if ($progids -ne 'com.example.Spiel.4bb1a8b546') { throw ".spiellevel's OpenWithProgids is '$progids'" }
$uninstallKey = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\com.example.Spiel'
if ($uninstallKey.URLInfoAbout -ne 'https://example.com/spiel') { throw "URLInfoAbout is '$($uninstallKey.URLInfoAbout)'" }
Write-Host "ok: the folders' verb, .spiellevel's $progids, and the uninstall key's URLInfoAbout"
Remove-Item -LiteralPath $report
Start-Process -FilePath (Join-Path $installed 'Spiel.exe') -ArgumentList "`"$report`"" -Wait
$out = (Get-Content -LiteralPath $report -Raw).Trim()
if ($out -ne $expected) { throw "unexpected report from the installed app: $out" }
Write-Host "ok: the installed app ran: $out"
$uninstall = Start-Process -FilePath (Join-Path $installed 'uninstall.exe') -ArgumentList '/S' -Wait -PassThru
if ($uninstall.ExitCode -ne 0) { throw "the uninstaller exited $($uninstall.ExitCode)" }

# The builder, given these, exits with Want, says Message, and writes
# nothing. The message tells a refusal from a Ruby that crashed with the
# same status.
function Assert-Refused {
  param([string] $Label, [int] $Want, [string] $Message, [string[]] $Arguments)
  $ErrorActionPreference = 'Continue'
  $output = & "$builder\Builder.exe" @Arguments 2>&1 | Out-String
  $status = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  Write-Host $output
  if ($status -ne $Want) { throw "$Label exited $status, not $Want" }
  if (-not $output.Contains($Message)) { throw "$Label does not say: $Message" }
  if (Test-Path 'Abgewiesen') { throw "$Label wrote Abgewiesen" }
  Write-Host "ok: $Label exits $status and says: $Message"
}

# A copy of the builder, as an app that Release built for OtherPlatform
# says it is in fledge.cfg's first line.
function New-Rewritten {
  param([string] $Folder, [string] $Release, [string] $OtherPlatform)
  Copy-Item -Recurse $builder $Folder
  $config = Join-Path $Folder 'fledge.cfg'
  $text = (Get-Content -LiteralPath $config -Raw) -replace '^# Written by fledge build \S+ for [^:]*:', "# Written by fledge build $Release for ${OtherPlatform}:"
  Set-Content -LiteralPath $config -Value $text -NoNewline -Encoding utf8NoBOM
}

Write-Host '== what --from refuses'
Copy-Item -Recurse $Game 'Mit Gemfile'
Set-Content -LiteralPath 'Mit Gemfile\Gemfile' -Value 'source "https://rubygems.org"'
Assert-Refused 'a project with a Gemfile' 1 '--from builds no gems' @('Mit Gemfile', 'Abgewiesen')

$current = [regex]::Match((Get-Content -LiteralPath "$builder\fledge.cfg" -TotalCount 1), 'fledge build (\S+) for').Groups[1].Value
New-Rewritten 'Andere Version' '0.0.1' $Platform
Assert-Refused 'an app of another release' $badAppStatus 'was built by Fledge 0.0.1' @('Mein Spiel', 'Abgewiesen', 'Andere Version')

New-Rewritten 'Andere Plattform' $current 'x86_64-linux'
Assert-Refused 'an app for another platform' $badAppStatus 'is an app for x86_64-linux' @('Mein Spiel', 'Abgewiesen', 'Andere Plattform')

New-Item -ItemType Directory 'Kein Fledge' | Out-Null
Set-Content -LiteralPath 'Kein Fledge\Spiel.exe' -Value 'not an app'
Assert-Refused 'a folder Fledge did not build' $badAppStatus 'is not an app fledge build wrote' @('Mein Spiel', 'Abgewiesen', 'Kein Fledge')

Write-Host "proved on $Platform"
