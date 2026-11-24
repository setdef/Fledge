# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of examples/lectern on Windows, as deliver-lectern.sh does on
# macOS and Linux: unpacks ARCHIVE, Lectern-PLATFORM.zip, in a folder
# whose name has a space and characters outside ASCII, and runs
# Lectern.exe on SAMPLE, a Markdown file, with only Windows' own folders
# on PATH. What it prints must be what bundle exec ruby main.rb printed
# on the Build job: PLAIN for the output of a pipe or a file, and COLORED
# for --color=always. It also reads the standard input, and a file it
# cannot read and an option it does not know end it with sysexits.h's
# EX_NOINPUT and EX_USAGE.
#
#   pwsh -NoProfile -File deliver-lectern.ps1 -Archive ARCHIVE -Sample SAMPLE -Plain PLAIN -Colored COLORED [-Work FOLDER]
#
# WORK is where the app is unpacked: RUNNER_TEMP on a runner, and the
# system's temporary folder elsewhere.

param(
  [Parameter(Mandatory)] [string] $Archive,
  [Parameter(Mandatory)] [string] $Sample,
  [Parameter(Mandatory)] [string] $Plain,
  [Parameter(Mandatory)] [string] $Colored,
  [string] $Work = $(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

function Fail([string] $message) {
  Write-Host "::error::Delivery (lectern): $message"
  exit 1
}

# A file's text as UTF-8, with Windows' line ends made Unix's, since
# Ruby's standard output on Windows writes each "\n" as "\r\n".
function Text([string] $path) {
  [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false)).Replace("`r`n", "`n")
}

$Archive = (Resolve-Path -LiteralPath $Archive).Path
$Sample = (Resolve-Path -LiteralPath $Sample).Path
$Plain = (Resolve-Path -LiteralPath $Plain).Path
$Colored = (Resolve-Path -LiteralPath $Colored).Path
$name = [IO.Path]::GetFileNameWithoutExtension($Archive)
$work = Join-Path $Work "lectern-$PID"
$place = Join-Path $work "h$([char]0xE9)llo w$([char]0xF6)rld"
New-Item -ItemType Directory -Force $place | Out-Null
Expand-Archive -LiteralPath $Archive -DestinationPath $place
$app = Join-Path (Join-Path $place $name) 'Lectern.exe'
if (-not (Test-Path -LiteralPath $app)) { Fail "$app is not in the archive" }
$notes = Join-Path $work 'notes.md'
Copy-Item -LiteralPath $Sample -Destination $notes

# The runner has Rubies; the app sees only Windows'.
$system = $env:SystemRoot
$env:PATH = "$system\System32;$system;$system\System32\WindowsPowerShell\v1.0"
if (Get-Command ruby -ErrorAction SilentlyContinue) { Fail "Get-Command still finds a Ruby on $env:PATH" }

# Runs Lectern with +$Arguments+, the standard input from +$In+ if given,
# and returns its exit status, its output, and its error.
function Run([string[]] $Arguments, [string] $In) {
  $out = Join-Path $work 'out'
  $err = Join-Path $work 'err'
  $parameters = @{
    FilePath = $app; ArgumentList = ($Arguments | ForEach-Object { "`"$_`"" }); NoNewWindow = $true; Wait = $true; PassThru = $true
    RedirectStandardOutput = $out; RedirectStandardError = $err
  }
  if ($In) { $parameters.RedirectStandardInput = $In }
  $process = Start-Process @parameters
  [pscustomobject]@{ Status = $process.ExitCode; Out = (Text $out); Err = (Text $err) }
}

$run = Run @($notes)
if ($run.Status -ne 0) { Write-Host $run.Err; Fail "Lectern exited with $($run.Status)" }
if ($run.Err.Length -ne 0) { Write-Host $run.Err; Fail 'Lectern wrote to standard error' }
if ($run.Out -cne (Text $Plain)) { Fail "Lectern printed other text than bundle exec: $($run.Out)" }
if ($run.Out.Contains([char]27)) { Fail 'Lectern wrote an escape sequence to a file' }
Write-Host 'ok: Lectern prints plain text to a file, as bundle exec does'

$run = Run @('--color=always', $notes)
if ($run.Status -ne 0) { Write-Host $run.Err; Fail "Lectern --color=always exited with $($run.Status)" }
if ($run.Out -cne (Text $Colored)) { Fail "Lectern printed other colors than bundle exec: $($run.Out)" }
if (-not $run.Out.Contains("$([char]27)[90;3m")) { Fail 'the colored output has no highlighted code' }
Write-Host 'ok: Lectern draws headings, emphasis, tables, and highlighted code as bundle exec does'

$run = Run @('-') $notes
if ($run.Status -ne 0) { Write-Host $run.Err; Fail "Lectern - exited with $($run.Status)" }
if ($run.Out -cne (Text $Plain)) { Fail "Lectern - printed other text than a file's: $($run.Out)" }
Write-Host 'ok: Lectern reads the standard input as it reads a file'

$missing = Join-Path $work 'missing.md'
$run = Run @($missing)
if ($run.Status -ne 66) { Fail "Lectern on a missing file exited with $($run.Status), not 66" }
if (-not $run.Err.Contains('No such file or directory')) { Fail "Lectern on a missing file said: $($run.Err)" }
$run = Run @('--nope')
if ($run.Status -ne 64) { Fail "Lectern --nope exited with $($run.Status), not 64" }
if (-not $run.Err.Contains('invalid option: --nope')) { Fail "Lectern --nope said: $($run.Err)" }
Write-Host 'ok: Lectern exits 66 on a file it cannot read and 64 on an option it does not know'

Write-Host 'Delivered: Lectern'
