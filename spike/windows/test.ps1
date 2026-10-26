# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# SPIKE: runs the built Windows apps somewhere else, with no Ruby on PATH
# and a hostile Ruby environment, and checks what they print.
# Usage: pwsh -File test.ps1 -Apps <dir with hello\, hello-full\, diag\>
param([Parameter(Mandatory)] [string] $Apps)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
$script:failures = 0
$expected = 'Hello from Ruby 4.0.9 on x64-mingw-ucrt'

function Section($title) { Write-Host "`n===== $title" }
function Check($ok, $what) {
  if ($ok) { Write-Host "PASS: $what" }
  else { Write-Host "::error::FAIL: $what"; $script:failures++ }
}
# Runs an exe; returns stdout lines, stderr text, and exit code.
function Invoke-App([string] $exe, [string[]] $argv = @()) {
  $errFile = New-TemporaryFile
  $out = & $exe @argv 2> $errFile.FullName
  $code = $LASTEXITCODE
  $err = Get-Content -Raw $errFile.FullName
  Remove-Item $errFile
  [pscustomobject]@{ Out = @($out); Err = $err; Code = $code }
}
function Show($r) {
  $r.Out | ForEach-Object { Write-Host "  out| $_" }
  if ($r.Err) { $r.Err -split "`r?`n" | Where-Object { $_ } | ForEach-Object { Write-Host "  err| $_" } }
  Write-Host "  exit: $($r.Code)"
}
function Expect-Hello($exe, $label) {
  $r = Invoke-App $exe
  Show $r
  Check (($r.Out -join "`n") -ceq $expected -and $r.Code -eq 0) "$label prints '$expected' and exits 0"
}
# PE optional header Subsystem: 2 = Windows GUI, 3 = Windows console.
function Get-Subsystem($exe) {
  $b = [IO.File]::ReadAllBytes($exe)
  $pe = [BitConverter]::ToInt32($b, 0x3C)
  [BitConverter]::ToUInt16($b, $pe + 24 + 68)
}

# --- Where: another drive, spaces and non-ASCII in the path ---------------
$name = "h$([char]0xE9)llo w$([char]0xF6)rld"
if (Test-Path 'D:\') { $root = Join-Path 'D:\Fledge test' $name }
else { $root = Join-Path (Join-Path $env:RUNNER_TEMP 'Fledge test') $name }
Section "Copying apps to $root"
Get-PSDrive -PSProvider FileSystem | Format-Table Name, Root, Used, Free | Out-String | Write-Host
New-Item -ItemType Directory -Force $root | Out-Null
Copy-Item -Recurse -Force (Join-Path $Apps '*') $root
Get-ChildItem $root | Format-Table Name, Length | Out-String | Write-Host

# --- No Ruby: strip PATH to Windows' own folders ---------------------------
Section 'Rubies on this runner, before stripping PATH'
& where.exe ruby 2>&1 | ForEach-Object { Write-Host "  $_" }
Get-ChildItem 'C:\hostedtoolcache\windows\Ruby' -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  toolcache: $($_.FullName)" }
Get-ChildItem 'C:\' -Filter 'Ruby*' -Directory -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  C:\: $($_.FullName)" }
Write-Host "  C:\msys64 present: $(Test-Path 'C:\msys64')"
$sys = $env:SystemRoot
$env:PATH = "$sys\System32;$sys;$sys\System32\Wbem;$sys\System32\WindowsPowerShell\v1.0"
Section "PATH is now: $env:PATH"
& where.exe ruby 2>&1 | Out-Null
Check ($LASTEXITCODE -ne 0) 'where ruby finds no Ruby'
& where.exe gcc 2>&1 | Out-Null
Check ($LASTEXITCODE -ne 0) 'where gcc finds no compiler'
Check ($null -eq (Get-Command ruby -ErrorAction SilentlyContinue)) 'Get-Command ruby finds nothing'

# Run from an unrelated working directory.
Set-Location $env:SystemRoot

# --- Clean environment ----------------------------------------------------
Section 'hello.exe, clean environment'
$gemrc = Join-Path $env:ProgramData 'gemrc'
$gemrcBefore = Test-Path $gemrc
Write-Host "  ProgramData\gemrc exists before: $gemrcBefore"
Expect-Hello (Join-Path $root 'hello\hello.exe') 'hello.exe'
Write-Host "  ProgramData\gemrc exists after: $(Test-Path $gemrc)"

# --- Hostile environment --------------------------------------------------
Section 'Hostile Ruby environment'
$hostile = 'C:\hostile'
New-Item -ItemType Directory -Force "$hostile\gems" | Out-Null
'raise "hostile RUBYLIB json.rb was loaded"' | Set-Content "$hostile\json.rb"
'raise "hostile Gemfile was loaded"' | Set-Content "$hostile\Gemfile"
$env:RUBYLIB = $hostile
$env:RUBYOPT = '-rnonexistent'
$env:GEM_HOME = "$hostile\gems"
$env:GEM_PATH = "$hostile\gems"
$env:GEM_SPEC_CACHE = "$hostile\specs"
$env:BUNDLE_GEMFILE = "$hostile\Gemfile"
$env:BUNDLE_PATH = "$hostile\bundle"
$env:bundle_lowercase_too = 'x'
$env:RUBY_DLL_PATH = $hostile
$env:RUBYSHELL = "$hostile\sh.exe"
Get-ChildItem env: | Where-Object Name -Match '^(RUBY|GEM_|BUNDLE_)' | Format-Table Name, Value | Out-String | Write-Host

Section 'hello.exe (min runtime), hostile'
Expect-Hello (Join-Path $root 'hello\hello.exe') 'hello.exe in a hostile environment'
Section 'hello-full.exe (unpruned runtime), hostile'
Expect-Hello (Join-Path $root 'hello-full\hello-full.exe') 'hello-full.exe in a hostile environment'
Section 'hello-nogems.exe (--disable-gems), hostile'
Expect-Hello (Join-Path $root 'hello\hello-nogems.exe') 'hello-nogems.exe in a hostile environment'

Section "Renamed copy: $name.exe"
$renamed = Join-Path $root "hello\$name.exe"
Copy-Item (Join-Path $root 'hello\hello.exe') $renamed
Expect-Hello $renamed 'a renamed, non-ASCII-named copy'

Section 'Exit status propagates'
$r = Invoke-App (Join-Path $root 'diag\diag.exe') @('exit3'); Show $r
Check ($r.Code -eq 3) 'exit 3 in main.rb exits 3'
$r = Invoke-App (Join-Path $root 'diag\diag.exe') @('raise'); Show $r
Check ($r.Code -eq 1 -and $r.Err -match 'boom from main.rb') 'an uncaught exception exits 1 with its message on stderr'

Section 'diag.exe report (gems enabled), hostile, with a non-ASCII argument'
$r = Invoke-App (Join-Path $root 'diag\diag.exe') @("w$([char]0xF6)rld", 'two words'); Show $r
Check ($r.Code -eq 0) 'diag.exe report exits 0'
Check (($r.Out -join "`n") -match 'require openssl: "ok"') 'openssl loads'
Check (($r.Out -join "`n") -match ('ARGV: \["w' + [char]0xF6 + 'rld", "two words"\]')) 'non-ASCII argv arrives intact'
Check (($r.Out -join "`n") -notmatch 'hostile') 'nothing in the report comes from the hostile environment'

Section 'diag-nogems.exe report (--disable-gems: no RubyInstaller hook)'
$r = Invoke-App (Join-Path $root 'diag\diag-nogems.exe'); Show $r
Check (($r.Out -join "`n") -match 'require openssl: "ok"') 'openssl loads without rubygems (manifests alone)'

Section 'diag-import.exe in ruby\bin (linked against the import library)'
$r = Invoke-App (Join-Path $root 'diag\ruby\bin\diag-import.exe'); Show $r
Check ($r.Code -eq 0) 'the import-linked launcher runs beside the DLL'
Section 'diag-import-toplevel.exe (import-linked, at the top, DLL not beside it)'
$r = Invoke-App (Join-Path $root 'diag\diag-import-toplevel.exe'); Show $r
Write-Host ('  exit code as hex: 0x{0:X8}' -f $r.Code)
Check ($r.Code -ne 0) 'the import-linked launcher cannot start away from the DLL'

# --- Windowed ----------------------------------------------------------------
Section 'Windowed (GUI subsystem) build'
foreach ($exe in 'hello\hello.exe', 'hello\hello-windowed.exe') {
  Write-Host "  $exe subsystem: $(Get-Subsystem (Join-Path $root $exe))"
}
Check ((Get-Subsystem (Join-Path $root 'hello\hello-windowed.exe')) -eq 2) 'hello-windowed.exe is a GUI-subsystem exe'
Check ((Get-Subsystem (Join-Path $root 'hello\hello.exe')) -eq 3) 'hello.exe is a console-subsystem exe'
$outFile = Join-Path $env:RUNNER_TEMP 'windowed-out.txt'
$p = Start-Process -FilePath (Join-Path $root 'hello\hello-windowed.exe') -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outFile
Write-Host "  Start-Process -Wait -RedirectStandardOutput: exit $($p.ExitCode), stdout: '$(Get-Content -Raw $outFile)'"
$r = Invoke-App (Join-Path $root 'hello\hello-windowed.exe'); Show $r
Write-Host '  (captured through a pipe with & in PowerShell)'
$sw = [Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath (Join-Path $root 'diag\diag-windowed.exe') -ArgumentList 'exit3' -Wait -PassThru
Write-Host "  windowed exit3, no redirection: exit $($p.ExitCode) in $($sw.ElapsedMilliseconds) ms"
Check ($p.ExitCode -eq 3) 'the windowed build propagates exit 3'

# --- Console encoding ----------------------------------------------------
Section 'Console code page and UTF-8 output'
Write-Host "  chcp: $(cmd /c chcp)"
Write-Host "  ACP: $((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').ACP), OEMCP: $((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').OEMCP)"
$raw = Join-Path $env:RUNNER_TEMP 'unicode.bin'
cmd /c "`"$(Join-Path $root 'diag\diag.exe')`" unicode > `"$raw`""
$hex = ([IO.File]::ReadAllBytes($raw) | ForEach-Object { $_.ToString('x2') }) -join ' '
Write-Host "  bytes written to a redirected stdout: $hex"
Check ($hex -eq '63 61 66 c3 a9 20 e2 9c 93 0a') 'UTF-8 bytes reach a redirected stdout unchanged'

# --- Long paths -------------------------------------------------------------
Section 'Long path (> 260 characters)'
$lp = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -ErrorAction SilentlyContinue
Write-Host "  LongPathsEnabled: $($lp.LongPathsEnabled)"
$deep = Join-Path $env:RUNNER_TEMP ((1..12 | ForEach-Object { 'a-rather-long-folder-name' }) -join '\')
New-Item -ItemType Directory -Force $deep | Out-Null
Copy-Item -Recurse (Join-Path $root 'hello') $deep
$deepExe = Join-Path $deep 'hello\hello.exe'
Write-Host "  exe path length: $($deepExe.Length)"
$r = Invoke-App $deepExe; Show $r
Check (($r.Out -join "`n") -ceq $expected) 'hello.exe runs from a path longer than MAX_PATH'

# --- Sizes ---------------------------------------------------------------
Section 'Sizes'
foreach ($app in 'hello', 'hello-full') {
  $dir = Join-Path $root $app
  $bytes = (Get-ChildItem -Recurse -File $dir | Measure-Object Length -Sum).Sum
  $zip = Join-Path $env:RUNNER_TEMP "$app.zip"
  Compress-Archive -Path "$dir\*" -DestinationPath $zip -CompressionLevel Optimal -Force
  Write-Host ("  {0}: {1:N1} MB unpacked, {2:N1} MB zipped, {3} files" -f $app, ($bytes / 1MB), ((Get-Item $zip).Length / 1MB), (Get-ChildItem -Recurse -File $dir).Count)
}

Section "Failures: $script:failures"
exit [int]($script:failures -gt 0)
