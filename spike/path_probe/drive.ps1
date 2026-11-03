# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Spike (experiment/path-probe only): drive.sh for Windows. Runs a built
# path probe in each scenario and keeps what it reports.
#
#   drive.ps1 -Archive NAME-PLATFORM.zip -Out OUTDIR -Label LABEL

param(
  [Parameter(Mandatory)] [string] $Archive,
  [Parameter(Mandatory)] [string] $Out,
  [Parameter(Mandatory)] [string] $Label
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path -LiteralPath $Out).Path
$Archive = (Resolve-Path -LiteralPath $Archive).Path
$folder = [IO.Path]::GetFileNameWithoutExtension($Archive)

$system = $env:SystemRoot
$systemPath = "$system\System32;$system;$system\System32\Wbem;$system\System32\WindowsPowerShell\v1.0"
$work = Join-Path $env:RUNNER_TEMP "probe-$Label"
New-Item -ItemType Directory -Force $work | Out-Null
$evil = Join-Path $work 'evil'
New-Item -ItemType Directory -Force $evil | Out-Null
Set-Content -LiteralPath (Join-Path $evil 'json.rb') -Value 'abort "the person RUBYLIB json.rb shadowed the runtime json"'
$personGems = Join-Path $work 'person gems'
New-Item -ItemType Directory -Force $personGems | Out-Null

$clean = @{
  SystemRoot = $system
  SystemDrive = $env:SystemDrive
  windir = $system
  PATH = $systemPath
  USERPROFILE = $env:USERPROFILE
  TEMP = $work
  TMP = $work
}
$person = $clean.Clone()
$person['RUBYOPT'] = '-W0'
$person['RUBYLIB'] = $evil
$person['GEM_HOME'] = $personGems
$person['GEM_PATH'] = $personGems
$hostile = $clean.Clone()
$hostile['RUBYLIB'] = $evil
$hostile['RUBYOPT'] = '-rnonexistent'
$hostile['RUBYGEMS_GEMDEPS'] = '-'
$hostile['GEM_HOME'] = Join-Path $env:USERPROFILE '.gem\ruby\4.0.0'
$hostile['GEM_PATH'] = Join-Path $env:USERPROFILE '.gem\ruby\4.0.0'
$hostile['GEMRC'] = Join-Path $evil 'gemrc'
$hostile['bundle_gemfile'] = Join-Path $evil 'Gemfile'
$hostile['BUNDLE_PATH'] = $evil
$hostile['BUNDLER_SETUP'] = Join-Path $evil 'bundler_setup.rb'
$hostile['RUBY_DLL_PATH'] = $evil
$hostile['RI_FORCE_PATH_FOR_DLL'] = '1'
$environments = @{ clean = $clean; person = $person; hostile = $hostile }

function Get-Program([string] $Place) {
  Get-ChildItem -LiteralPath (Join-Path $Place $folder) -Filter '*.exe' | Select-Object -First 1 -ExpandProperty FullName
}

function Invoke-Run([string] $Run, [string] $EnvKind, [string] $Mode, [string] $Place) {
  $outFile = Join-Path $Out "$Label--$Run.jsonl"
  Remove-Item -LiteralPath $outFile -ErrorAction SilentlyContinue
  $program = Get-Program $Place
  $info = [Diagnostics.ProcessStartInfo]::new($program)
  foreach ($argument in @($outFile, $Mode, '0')) { $info.ArgumentList.Add($argument) }
  $info.UseShellExecute = $false
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
  $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
  $info.WorkingDirectory = $system
  $info.Environment.Clear()
  $environment = $environments[$EnvKind]
  foreach ($name in $environment.Keys) { $info.Environment[$name] = $environment[$name] }
  $process = [Diagnostics.Process]::Start($info)
  $errors = $process.StandardError.ReadToEndAsync()
  $stdout = $process.StandardOutput.ReadToEnd()
  $process.WaitForExit()
  $head = [ordered]@{ run = $Run; env = $EnvKind; mode = $Mode; place = $Place; program = $program; status = $process.ExitCode }
  $text = ($head | ConvertTo-Json -Compress) + "`n" + $errors.GetAwaiter().GetResult() + $stdout
  [IO.File]::WriteAllText((Join-Path $Out "$Label--$Run.result"), $text, [Text.UTF8Encoding]::new($false))
  Write-Host "== $Label ${Run}: status $($process.ExitCode)"
  Write-Host $errors.GetAwaiter().GetResult()
  if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile -Encoding utf8 | Write-Host }
}

# Built: the folder fledge build left beside the archive.
$built = Split-Path -Parent $Archive
if (Test-Path -LiteralPath (Join-Path $built $folder)) { Invoke-Run 'built-clean-ruby' 'clean' 'ruby' $built }

$unpacked = Join-Path $work 'unpacked'
New-Item -ItemType Directory -Force $unpacked | Out-Null
Expand-Archive -LiteralPath $Archive -DestinationPath $unpacked
Invoke-Run 'unpacked-clean-ruby' 'clean' 'ruby' $unpacked

$moved = Join-Path $work 'moved\elsewhere'
New-Item -ItemType Directory -Force $moved | Out-Null
Move-Item -LiteralPath (Join-Path $unpacked $folder) -Destination $moved
Invoke-Run 'moved-clean-ruby' 'clean' 'ruby' $moved

$drive = if (Test-Path 'D:\') { 'D:\' } else { $env:RUNNER_TEMP }
$place = Join-Path (Join-Path $drive "My Apps $Label") "$([char]0xDC)n$([char]0xEF)c$([char]0xF6)d$([char]0xE9) $([char]0x65E5)$([char]0x672C)"
New-Item -ItemType Directory -Force $place | Out-Null
Move-Item -LiteralPath (Join-Path $moved $folder) -Destination $place
foreach ($envKind in 'clean', 'person', 'hostile') {
  foreach ($mode in 'ruby', 'launcher', 'scrubbed') {
    Invoke-Run "unicode-$envKind-$mode" $envKind $mode $place
  }
}

# As Explorer starts a program: through the shell, with this process's
# environment less its Ruby.
$env:PATH = $systemPath
foreach ($name in @(Get-ChildItem env: | Where-Object { $_.Name -match '^(RUBY|GEM_|GEMRC|BUNDLE_|BUNDLER_)' } | ForEach-Object Name)) {
  Remove-Item "env:$name"
}
foreach ($mode in 'ruby', 'launcher') {
  $run = "shell-clean-$mode"
  $outFile = Join-Path $Out "$Label--$run.jsonl"
  $program = Get-Program $place
  $process = Start-Process -FilePath $program -ArgumentList "`"$outFile`"", $mode, '0' -WorkingDirectory $system -Wait -PassThru
  $head = [ordered]@{ run = $run; env = 'shell'; mode = $mode; place = $place; program = $program; status = $process.ExitCode }
  [IO.File]::WriteAllText((Join-Path $Out "$Label--$run.result"), ($head | ConvertTo-Json -Compress) + "`n", [Text.UTF8Encoding]::new($false))
  Write-Host "== $Label ${run}: status $($process.ExitCode)"
  if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile -Encoding utf8 | Write-Host }
}
exit 0
