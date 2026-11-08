# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Delivery of one project's several programs (ADR 024) on Windows:
# unpacks what fledge build wrote for examples/programs, checks that the
# folder holds one copy of the project and one Ruby, and runs both
# programs from it, with no Ruby anywhere they can reach.
#
#   pwsh -NoProfile -File deliver-programs.ps1 -Archive ARCHIVE
#
# ARCHIVE is "Shared Save-x64-mingw-ucrt.zip", or aarch64-mingw-ucrt's.
# Its folder holds Shared Save.exe, a GUI program, and shared-save.exe, a
# console one, each named in its own version information. The console
# program prints each entry of the save it is given and adds its own; the
# windowed one, started as Explorer starts it, writes what it read to a
# report and adds its own. Each entry names the real path of the project
# and of Ruby's library the program ran, which must be the same for
# both, inside the folder. Nothing here may need Ruby.

param(
  [Parameter(Mandatory)] [string] $Archive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$windowedName = 'Shared Save'
$consoleName = 'shared-save'

function Fail([string] $message) {
  Write-Host "::error::Delivery (programs): $message"
  exit 1
}

function Expect([string] $Label, $Actual, $Expected) {
  if ($Actual -cne $Expected) { Fail "$Label is '$Actual', not '$Expected'" }
  Write-Host "ok: $Label is $Expected"
}

$Archive = (Resolve-Path -LiteralPath $Archive).Path
$name = [IO.Path]::GetFileNameWithoutExtension($Archive)
$drive = if (Test-Path 'D:\') { 'D:\' } else { $env:RUNNER_TEMP }
$place = Join-Path (Join-Path $drive 'Fledge programs') "h$([char]0xE9)llo w$([char]0xF6)rld"
New-Item -ItemType Directory -Force $place | Out-Null
Expand-Archive -LiteralPath $Archive -DestinationPath $place
$root = Join-Path $place $name
$windowed = Join-Path $root "$windowedName.exe"
$console = Join-Path $root "$consoleName.exe"
foreach ($program in @($windowed, $console)) {
  if (-not (Test-Path -LiteralPath $program -PathType Leaf)) { Fail "$program is missing after unpacking $Archive" }
}

# How Windows runs each, as its shell says (SHGetFileInfo with
# SHGFI_EXETYPE): a Win32 program (PE in the low word) that asks for a
# Windows version (the high word) is a GUI one; a console one asks none.
Add-Type -Namespace Fledge -Name Shell -MemberDefinition @'
[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr SHGetFileInfo(string path, uint attributes, IntPtr info, uint size, uint flags);
'@
function Kind([string] $path) {
  $type = [Fledge.Shell]::SHGetFileInfo($path, 0, [IntPtr]::Zero, 0, 0x2000).ToInt64()
  if (($type -band 0xFFFF) -ne 0x4550) { return "not a Win32 program ($type)" }
  if (($type -shr 16) -ne 0) { return 'GUI' }
  'console'
}
Expect "the kind of $windowedName.exe" (Kind $windowed) 'GUI'
Expect "the kind of $consoleName.exe" (Kind $console) 'console'
Expect "$windowedName.exe's FileDescription" (Get-Item -LiteralPath $windowed).VersionInfo.FileDescription $windowedName
Expect "$consoleName.exe's FileDescription" (Get-Item -LiteralPath $console).VersionInfo.FileDescription $consoleName

# One project and one Ruby: each file of either is in the folder once.
foreach ($file in @('window.rb', 'shared_save.rb', 'fledge.yml', 'rbconfig.rb')) {
  $count = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter $file).Count
  Expect "the copies of $file" $count 1
}

# The runner has Rubies; the programs' PATH keeps only Windows' own
# folders.
$system = $env:SystemRoot
$env:PATH = "$system\System32;$system;$system\System32\Wbem;$system\System32\WindowsPowerShell\v1.0"
if (Get-Command ruby -ErrorAction SilentlyContinue) { Fail "Get-Command still finds a Ruby on $env:PATH" }

$save = Join-Path $env:RUNNER_TEMP 'programs save.jsonl'
$report = Join-Path $env:RUNNER_TEMP 'programs report.json'
Remove-Item -LiteralPath $save, $report -ErrorAction SilentlyContinue

# Console: runs the console program, failing unless it exits with 0,
# and returns what it printed, one line each.
function Console([string] $label) {
  $out = & $console $save 2>&1
  if ($LASTEXITCODE -ne 0) { Fail "$label exited with $LASTEXITCODE`: $out" }
  @($out | Where-Object { $_ -ne '' })
}

$first = @(Console "$consoleName.exe, first")
Expect "the entries $consoleName.exe found in no save" $first.Count 0
$process = Start-Process -FilePath $windowed -ArgumentList "`"$save`"", "`"$report`"" -WorkingDirectory $system -Wait -PassThru
Expect "$windowedName.exe's exit status" $process.ExitCode 0
$read = @((Get-Content -LiteralPath $report -Raw | ConvertFrom-Json).read)
Expect "the entries $windowedName.exe read" ($read | ForEach-Object { $_.by }) $consoleName
$lines = @(Console "$consoleName.exe, again")
$entries = @($lines | ForEach-Object { $_ | ConvertFrom-Json })
Expect "the entries $consoleName.exe read" (($entries | ForEach-Object { $_.by }) -join ', ') "$consoleName, $windowedName"

# The project and the Ruby each program ran, which must be one of each,
# in the folder.
$realRoot = (Get-Item -LiteralPath $root).FullName
foreach ($key in @('project', 'ruby')) {
  $values = @($entries | ForEach-Object { $_.$key } | Sort-Object -Unique)
  Expect "the number of ${key}s the programs ran" $values.Count 1
  $value = $values[0] -replace '/', '\'
  if (-not $value.StartsWith("$realRoot\", [StringComparison]::OrdinalIgnoreCase)) { Fail "the $key, $value, is not in the folder, $realRoot" }
  Write-Host "ok: both programs ran the $key at $($value.Substring($realRoot.Length + 1))"
}

# A copy renamed by hand finds no program of its name.
$renamed = Join-Path $root 'renamed.exe'
Copy-Item -LiteralPath $console -Destination $renamed
$out = & $renamed $save 2>&1
Expect "a renamed program's exit status" $LASTEXITCODE 66
if (-not ("$out" -match 'has no program named renamed')) { Fail "a renamed program did not say what it was missing: $out" }
Write-Host "ok: a renamed program exits with 66: $out"

Write-Host "Delivered: $windowedName and $consoleName, from one folder"
