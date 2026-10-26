# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Delivery (Plan 001) on Windows: runs a built examples/hello the way a
# person who has never installed Ruby would, and fails unless it behaves.
# It is deliver.sh's counterpart, with the same checks where Windows has
# them, and more where Windows has more ways in.
#
#   pwsh -NoProfile -File deliver.ps1 -Archive ARCHIVE -Platform RUBY_PLATFORM
#
# ARCHIVE is hello-PLATFORM.zip as fledge build wrote it. RUBY_PLATFORM is
# what the app must report: x64-mingw-ucrt.
#
# Each run goes through .NET's Process, which waits for the program and
# captures both of its streams: PowerShell's & operator neither waits for
# nor captures a GUI-subsystem program, which a windowed app will be, and
# Start-Process cannot capture both streams into variables. Nothing here
# may need Ruby.

param(
  [Parameter(Mandatory)] [string] $Archive,
  [Parameter(Mandatory)] [string] $Platform
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$expected = "Hello from Ruby 4.0.9 on $Platform"

function Fail([string] $message) {
  Write-Host "::error::Delivery: $message"
  exit 1
}

# Runs $Program with exactly $Environment as its environment, from
# $Directory, and returns what it printed and its exit status.
function Invoke-App([string] $Program, [hashtable] $Environment, [string[]] $Arguments = @(),
  [string] $Directory = $env:SystemRoot) {
  $info = [Diagnostics.ProcessStartInfo]::new($Program)
  foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
  $info.UseShellExecute = $false
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
  $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
  $info.WorkingDirectory = $Directory
  $info.Environment.Clear()
  foreach ($name in $Environment.Keys) { $info.Environment[$name] = $Environment[$name] }
  $process = [Diagnostics.Process]::Start($info)
  $errors = $process.StandardError.ReadToEndAsync()
  $out = $process.StandardOutput.ReadToEnd()
  $process.WaitForExit()
  [pscustomobject]@{ Out = $out; Err = $errors.GetAwaiter().GetResult(); Code = $process.ExitCode }
}

# Fails unless the run printed exactly the expected line, nothing on
# standard error, and exited with $Status.
function Check([string] $Label, [int] $Status, [string] $Program, [hashtable] $Environment,
  [string[]] $Arguments = @(), [string] $Directory = $env:SystemRoot) {
  $run = Invoke-App $Program $Environment $Arguments $Directory
  if ($run.Out -cnotmatch "\A$([regex]::Escape($expected))\r?\n\z" -or $run.Err -ne '' -or $run.Code -ne $Status) {
    Write-Host '--- stdout'
    Write-Host $run.Out
    Write-Host '--- stderr'
    Write-Host $run.Err
    Fail "${Label}: exit status $($run.Code) (expected $Status), output above (expected `"$expected`")"
  }
  Write-Host "ok: $Label"
}

# The Subsystem field of a program's PE optional header: 2 is a GUI
# program, 3 a console one.
function Get-Subsystem([string] $Program) {
  $bytes = [IO.File]::ReadAllBytes($Program)
  $header = [BitConverter]::ToInt32($bytes, 0x3C)
  [BitConverter]::ToUInt16($bytes, $header + 24 + 68)
}

# What is in a folder, to tell whether running the app wrote to it.
function Get-Snapshot([string] $Folder) {
  (Get-ChildItem -LiteralPath $Folder -Recurse -Force | ForEach-Object {
      "$($_.FullName)|$(if ($_.PSIsContainer) { 'dir' } else { $_.Length })"
    } | Sort-Object) -join "`n"
}

# Unpack somewhere the app was never built, on another drive when the
# runner has one, under a folder with a space and characters outside
# ASCII, with Windows' own Expand-Archive, as a person would.
$Archive = (Resolve-Path -LiteralPath $Archive).Path
$name = [IO.Path]::GetFileNameWithoutExtension($Archive)
$folderName = "h$([char]0xE9)llo w$([char]0xF6)rld"
$drive = if (Test-Path 'D:\') { 'D:\' } else { $env:RUNNER_TEMP }
$place = Join-Path (Join-Path $drive 'Fledge test') $folderName
New-Item -ItemType Directory -Force $place | Out-Null
Expand-Archive -LiteralPath $Archive -DestinationPath $place
$root = Join-Path $place $name
$app = Join-Path $root 'hello.exe'
if (-not (Test-Path -LiteralPath $app -PathType Leaf)) { Fail "$app is missing after unpacking $Archive" }
if ((Get-Subsystem $app) -ne 3) { Fail "$app is not a console program (PE subsystem $(Get-Subsystem $app))" }
Write-Host "Unpacked to $root"

# The runner has Rubies (on PATH, in C:\hostedtoolcache, MSYS2 in
# C:\msys64). PATH keeps only Windows' own folders, and nothing on it may
# find a Ruby or a compiler.
$own = Get-Command ruby -ErrorAction SilentlyContinue
Write-Host "This computer's own Ruby: $(if ($own) { $own.Source } else { 'none' })"
$system = $env:SystemRoot
$env:PATH = "$system\System32;$system;$system\System32\Wbem;$system\System32\WindowsPowerShell\v1.0"
& where.exe ruby *> $null
if ($LASTEXITCODE -eq 0) { Fail "where ruby still finds a Ruby on $env:PATH" }
& where.exe gcc *> $null
if ($LASTEXITCODE -eq 0) { Fail "where gcc still finds a compiler on $env:PATH" }
if (Get-Command ruby -ErrorAction SilentlyContinue) { Fail "Get-Command still finds a Ruby on $env:PATH" }
Write-Host "No Ruby or compiler on the app's PATH: $env:PATH"

$work = Join-Path $env:RUNNER_TEMP 'delivery'
New-Item -ItemType Directory -Force $work | Out-Null

# The environment a desktop gives a program, and nothing else: Windows'
# own folders, the person's profile, and a temporary folder.
$clean = @{
  SystemRoot = $system
  SystemDrive = $env:SystemDrive
  windir = $system
  PATH = $env:PATH
  USERPROFILE = $env:USERPROFILE
  TEMP = $work
  TMP = $work
}

# A renamed copy, as fledge build renames the launcher for each app: its
# manifest is inside it, so it travels with the file.
$renamed = Join-Path $root "$folderName.exe"
Copy-Item -LiteralPath $app -Destination $renamed
$before = Get-Snapshot $place

Check 'clean environment' 0 $app $clean
Check 'exit status 3 reaches the caller' 3 $app $clean @('3')
Check "a renamed copy, $folderName.exe" 0 $renamed $clean

# A json 99 in the person's own gem folder (Gem.user_dir:
# %USERPROFILE%\.local\share\gem\ruby\4.0.0, or %USERPROFILE%\.gem\ruby\4.0.0
# once %USERPROFILE%\.gem exists) shadows the runtime's json if RubyGems
# searches it, and raises if it ever loads.
$leak = 'raise "Delivery: the user''s Ruby environment leaked into the app"'
function Install-LeakingJson([string] $GemFolder) {
  New-Item -ItemType Directory -Force (Join-Path $GemFolder 'gems\json-99.0.0\lib'), (Join-Path $GemFolder 'specifications') |
    Out-Null
  Set-Content -LiteralPath (Join-Path $GemFolder 'gems\json-99.0.0\lib\json.rb') -Value $leak
  Set-Content -LiteralPath (Join-Path $GemFolder 'specifications\json-99.0.0.gemspec') -Value @'
Gem::Specification.new do |s|
  s.name = "json"
  s.version = "99.0.0"
  s.summary = "leak"
  s.authors = ["leak"]
  s.files = ["lib/json.rb"]
end
'@
}
$xdgGems = Join-Path $env:USERPROFILE '.local\share\gem\ruby\4.0.0'
Install-LeakingJson $xdgGems
Check 'a json gem in %USERPROFILE%\.local\share\gem' 0 $app $clean
$dotGems = Join-Path $env:USERPROFILE '.gem\ruby\4.0.0'
Install-LeakingJson $dotGems
Check 'a json gem in %USERPROFILE%\.gem' 0 $app $clean

# A hostile environment: everything a Ruby developer's shell might set,
# pointed at code that raises if it ever loads. Windows' variable names
# ignore case, so a lowercase bundle_gemfile is Bundler's BUNDLE_GEMFILE.
# RUBY_DLL_PATH and RI_FORCE_PATH_FOR_DLL are RubyInstaller's own.
$evil = Join-Path $work 'evil'
New-Item -ItemType Directory -Force $evil | Out-Null
foreach ($file in 'json.rb', 'nonexistent.rb', 'bundler_setup.rb', 'Gemfile', 'gemrc') {
  Set-Content -LiteralPath (Join-Path $evil $file) -Value $leak
}
$hostile = $clean.Clone()
$hostile['RUBYLIB'] = $evil
$hostile['RUBYOPT'] = '-rnonexistent'
$hostile['RUBYSHELL'] = Join-Path $evil 'sh.exe'
$hostile['RUBYGEMS_GEMDEPS'] = '-'
$hostile['GEM_HOME'] = $dotGems
$hostile['GEM_PATH'] = $dotGems
$hostile['GEM_SPEC_CACHE'] = $evil
$hostile['GEMRC'] = Join-Path $evil 'gemrc'
$hostile['bundle_gemfile'] = Join-Path $evil 'Gemfile'
$hostile['BUNDLE_PATH'] = $evil
$hostile['BUNDLER_SETUP'] = Join-Path $evil 'bundler_setup.rb'
$hostile['RUBY_DLL_PATH'] = $evil
$hostile['RI_FORCE_PATH_FOR_DLL'] = '1'
Check 'hostile environment' 0 $app $hostile

# DLLs that are not DLLs, named as Ruby's and its libraries' are, on
# PATH and in the current folder: Windows would load them before the
# runtime's own if the launcher let it search either.
foreach ($dll in 'x64-ucrt-ruby400.dll', 'libgmp-10.dll', 'libwinpthread-1.dll', 'zlib1.dll', 'libyaml-0-2.dll',
  'libssl-3-x64.dll', 'libcrypto-3-x64.dll') {
  Set-Content -LiteralPath (Join-Path $evil $dll) -Value 'not a DLL'
}
$planted = $hostile.Clone()
$planted['PATH'] = "$evil;$($clean['PATH'])"
Check 'DLLs planted on PATH and in the current folder' 0 $app $planted @() $evil

# Running the app writes nothing into its own folder, as RubyInstaller's
# RubyGems defaults would (a writable_p probe in the gem folder).
if ((Get-Snapshot $place) -ne $before) { Fail "running the app changed the files in $place" }
Write-Host 'ok: the app wrote nothing into its own folder'

# A broken app fails with a message that names the app, not Ruby, on
# standard error, and the launcher's own exit status, 70.
$main = Join-Path $root 'app\main.rb'
Move-Item -LiteralPath $main -Destination "$main.away"
$broken = Invoke-App $app $clean
Move-Item -LiteralPath "$main.away" -Destination $main
$message = "\Ahello\.exe: this app is incomplete: $([regex]::Escape($main)) is missing\r?\n\z"
if ($broken.Code -ne 70 -or $broken.Out -ne '' -or $broken.Err -cnotmatch $message) {
  Write-Host "--- stdout`n$($broken.Out)--- stderr`n$($broken.Err)"
  Fail "an app without main.rb: exit status $($broken.Code) (expected 70), output above"
}
Write-Host 'ok: an app without main.rb says so and exits 70'

Write-Host "Delivered: $expected"
