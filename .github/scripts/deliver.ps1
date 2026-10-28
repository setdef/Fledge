# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Delivery (Plan 001) on Windows: runs a built app the way a person who
# has never installed Ruby would, and fails unless it behaves. It is
# deliver.sh's counterpart, with the same checks where Windows has them,
# and more where Windows has more ways in. CI delivers examples/hello and
# examples/my_cool_app (ADR 005).
#
#   pwsh -NoProfile -File deliver.ps1 -Archive ARCHIVE -Probe PROBE_ARCHIVE -Platform PLATFORM -Expected LINE
#
# ARCHIVE is NAME-PLATFORM.zip as fledge build wrote it, and PROBE_ARCHIVE
# the parity probe (test/fixtures/parity) built the same way, which
# reports what a child Ruby sees: Parity-PLATFORM.zip, a lone script, for
# hello, and ParityBundle-PLATFORM.zip, the probe as a gem-shaped app's
# program (Parity.gem_probe), for my_cool_app. PLATFORM is x64-mingw-ucrt,
# and LINE the one line the app must print.
#
# Each run goes through .NET's Process, which waits for the program and
# captures both of its streams: PowerShell's & operator neither waits for
# nor captures a GUI-subsystem program, which a windowed app will be, and
# Start-Process cannot capture both streams into variables. Nothing here
# may need Ruby.

param(
  [Parameter(Mandatory)] [string] $Archive,
  [Parameter(Mandatory)] [string] $Probe,
  [Parameter(Mandatory)] [string] $Platform,
  [Parameter(Mandatory)] [string] $Expected
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$expected = $Expected

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

# What is in a folder, to tell whether running the app wrote to it: a
# Bundler that touched or rewrote the Gemfile.lock would, on every start.
function Get-Snapshot([string] $Folder) {
  (Get-ChildItem -LiteralPath $Folder -Recurse -Force | ForEach-Object {
      "$($_.FullName)|$(if ($_.PSIsContainer) { 'dir' } else { "$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" })"
    } | Sort-Object) -join "`n"
}

# Unpack somewhere the app was never built, on another drive when the
# runner has one, under a folder with a space and characters outside
# ASCII, with Windows' own Expand-Archive, as a person would.
$Archive = (Resolve-Path -LiteralPath $Archive).Path
$name = [IO.Path]::GetFileNameWithoutExtension($Archive)
$folderName = "h$([char]0xE9)llo w$([char]0xF6)rld"
$drive = if (Test-Path 'D:\') { 'D:\' } else { $env:RUNNER_TEMP }
$place = Join-Path (Join-Path (Join-Path $drive 'Fledge test') $name) $folderName
New-Item -ItemType Directory -Force $place | Out-Null
Expand-Archive -LiteralPath $Archive -DestinationPath $place
$Probe = (Resolve-Path -LiteralPath $Probe).Path
Expand-Archive -LiteralPath $Probe -DestinationPath $place
$probeBase = [IO.Path]::GetFileNameWithoutExtension($Probe)
$probeFolder = Join-Path $place $probeBase
$probeApp = Join-Path $probeFolder "$($probeBase.Substring(0, $probeBase.Length - $Platform.Length - 1)).exe"
$root = Join-Path $place $name
$appName = $name.Substring(0, $name.Length - $Platform.Length - 1)
$app = Join-Path $root "$appName.exe"
$entry = ((Get-Content -LiteralPath (Join-Path $root 'fledge.cfg')) -match '^entry = ' | Select-Object -First 1) -replace '^entry = ', ''
if (-not $entry) { Fail "$root\fledge.cfg names no entry" }
if (-not (Test-Path -LiteralPath $app -PathType Leaf)) { Fail "$app is missing after unpacking $Archive" }
if ((Get-Subsystem $app) -ne 3) { Fail "$app is not a console program (PE subsystem $(Get-Subsystem $app))" }
Write-Host "Unpacked to $root"

# A console app carries version information too (ADR 008): Task Manager
# and Explorer name it by its FileDescription and ProductName, which
# default to the app's name.
$info = (Get-Item -LiteralPath $app).VersionInfo
foreach ($pair in @(@('FileDescription', $appName), @('ProductName', $appName), @('OriginalFilename', "$appName.exe"))) {
  if ($info.($pair[0]) -cne $pair[1]) { Fail "$appName.exe's $($pair[0]) is '$($info.($pair[0]))', not '$($pair[1])'" }
}
Write-Host "ok: $appName.exe names itself $appName, version $($info.ProductVersion)"

# The app carries the notices the license audit wrote (ADR 004): every
# component and license text, GMP's replaceability and source among them,
# and the SBOM.
$notices = Join-Path $root 'notices\NOTICES.txt'
if (-not (Test-Path -LiteralPath (Join-Path $root 'notices\sbom.spdx.json') -PathType Leaf)) { Fail "the app has no notices\sbom.spdx.json" }
if (-not (Test-Path -LiteralPath $notices -PathType Leaf)) { Fail "the app has no notices\NOTICES.txt" }
$text = Get-Content -LiteralPath $notices -Raw
foreach ($line in @('This app was built with Fledge', '  ruby/bin/ruby_builtin_dlls/libgmp-10.dll', '-x64-mingw-ucrt-lgpl-sources.tar.gz')) {
  if (-not $text.Contains($line)) { Fail "notices\NOTICES.txt does not say '$line'" }
}
Write-Host "ok: the app carries its notices and SBOM"

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
# A %USERPROFILE%\.bundle\config that points Bundler elsewhere, asks for
# gems compiled from source, leaves out the app's own gems, and installs
# whatever is missing, which the app's Bundler must never read.
New-Item -ItemType Directory -Force (Join-Path $env:USERPROFILE '.bundle') | Out-Null
Set-Content -LiteralPath (Join-Path $env:USERPROFILE '.bundle\config') -Value @"
---
BUNDLE_GEMFILE: "$($work -replace '\\', '/')/evil/Gemfile"
BUNDLE_PATH: "$($work -replace '\\', '/')/evil"
BUNDLE_FORCE_RUBY_PLATFORM: "true"
BUNDLE_WITHOUT: "default"
BUNDLE_AUTO_INSTALL: "true"
"@
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
$hostile['BUNDLE_APP_CONFIG'] = $evil
$hostile['BUNDLE_FROZEN'] = 'false'
$hostile['BUNDLE_WITHOUT'] = 'default'
$hostile['BUNDLER_VERSION'] = '2.1.0'
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

# The person's own Ruby settings are hidden from the app's boot only
# (ADR 003): the app's gems stay the runtime's, and what the app starts
# sees the person's GEM_HOME and RUBYOPT. Without a Gemfile, that is any
# Ruby the app starts through RbConfig.ruby, the runtime's own ruby.exe,
# as under ruby main.rb. With one, the app's ENV is bundle exec's, with
# Bundler's GEM_HOME over the person's, and a Ruby started inside
# Bundler.with_original_env or with_unbundled_env, as a Bundler app
# starts a person's own tools, sees theirs (ADR 005).
$personGems = Join-Path $work 'person gems'
New-Item -ItemType Directory -Force $personGems | Out-Null
$person = $clean.Clone()
$person['GEM_HOME'] = $personGems
$person['RUBYOPT'] = '-W0'
$commands = if (Test-Path -LiteralPath (Join-Path $probeFolder 'app\Gemfile')) {
  @('original-child-env', 'unbundled-child-env')
} else {
  @('child-env')
}
foreach ($command in $commands) {
  foreach ($variable in @(@('GEM_HOME', $personGems), @('RUBYOPT', '-W0'))) {
    $seen = Invoke-App $probeApp $person @($command, $variable[0])
    if ($seen.Code -ne 0 -or $seen.Out.TrimEnd() -cne $variable[1]) {
      Write-Host "--- stdout`n$($seen.Out)--- stderr`n$($seen.Err)"
      Fail "${command}: a child Ruby saw $($variable[0]) as '$($seen.Out.TrimEnd())', not the person's '$($variable[1])'"
    }
  }
}
Write-Host "ok: a child Ruby started by $($commands -join ' and ') sees the person's GEM_HOME and RUBYOPT"
$gemPath = Invoke-App $probeApp $person @('gem-path')
if ($gemPath.Code -ne 0 -or $gemPath.Out.Replace('/', '\').Contains($personGems)) {
  Write-Host "--- stdout`n$($gemPath.Out)--- stderr`n$($gemPath.Err)"
  Fail "the app's own Gem.path holds the person's GEM_HOME"
}
Write-Host "ok: the app's own gems ignore the person's GEM_HOME"

# A broken app fails with a message that names the app, not Ruby, on
# standard error, and EX_NOINPUT (66) when the program it runs, app\ENTRY,
# is missing (ADR 002).
$program = Join-Path $root ('app\' + $entry.Replace('/', '\'))
Move-Item -LiteralPath $program -Destination "$program.away"
$broken = Invoke-App $app $clean
Move-Item -LiteralPath "$program.away" -Destination $program
$message = "\A$([regex]::Escape("$appName.exe")): this app is incomplete: $([regex]::Escape($program)) is missing\r?\n\z"
if ($broken.Code -ne 66 -or $broken.Out -ne '' -or $broken.Err -cnotmatch $message) {
  Write-Host "--- stdout`n$($broken.Out)--- stderr`n$($broken.Err)"
  Fail "an app without app\${entry}: exit status $($broken.Code) (expected 66), output above"
}
Write-Host "ok: an app without app\$entry says so and exits 66"

Write-Host "Delivered: $expected"
