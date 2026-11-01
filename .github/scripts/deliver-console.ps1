# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Delivery of the console on Windows (ADR 015): runs the console probe
# (test/fixtures/console) in a console of its own, as a person runs an
# app in a console window, and ends it as they would:
#
#   interrupt  Ctrl-C, which GenerateConsoleCtrlEvent sends to every
#              process on the console, as the console does when a person
#              types it. Ruby's C runtime turns it into SIGINT, and Ruby
#              raises Interrupt; uncaught, it runs ensure clauses and
#              at_exit hooks, and ends by SIGINT, which on Windows is
#              exit code 3. Once with the console's code page UTF-8 (65001)
#              and once with 437, the default of an English Windows
#              console: the probe's line outside ASCII must appear on the
#              console as written, and Ruby must choose the encoding
#              ruby.exe chooses for that code page.
#   close      The console's window closing, which sends CTRL_CLOSE_EVENT
#              to every process on it. Ruby handles none, so Windows ends
#              the probe at once, with STATUS_CONTROL_C_EXIT, before any
#              ensure clause runs, as it ends ruby.exe.
#
# And a windowed app (ADR 008) started from a console, as a person types
# its name into one: like rubyw.exe, it gets no console, and the console
# does not wait for it.
#
#   deliver-console.ps1 -Archive Console-x64-mingw-ucrt.zip -Windowed "Hello Window-x64-mingw-ucrt.zip"
#   deliver-console.ps1 -Reference RUBY.EXE,MAIN_RB -WindowedReference RUBYW.EXE,WINDOWED_MAIN_RB
#
# With -Reference, it runs the probe's own main.rb with ruby.exe, and
# windowed_app's main.rb with rubyw.exe, and expects exactly the same;
# CI's Test job runs that with RubyInstaller's Ruby, and Delivery the
# built apps. The launcher calls nothing that changes how the console's
# events reach Ruby: Ruby's DLL, which it loads, sets up its own
# handling as it does in ruby.exe.
#
# -Inner is how the script runs itself in a new console; it is not for
# callers.

param(
  [string] $Archive,
  [string] $Windowed,
  [string[]] $Reference,
  [string[]] $WindowedReference,
  [string] $Inner,
  [string] $Work
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

Add-Type -Namespace Fledge -Name Console -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct Coord { public short X; public short Y; }
[StructLayout(LayoutKind.Sequential)]
public struct Rect { public short Left; public short Top; public short Right; public short Bottom; }
[StructLayout(LayoutKind.Sequential)]
public struct BufferInfo { public Coord Size; public Coord Cursor; public ushort Attributes; public Rect Window; public Coord MaximumWindow; }

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleCP(uint codePage);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleOutputCP(uint codePage);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleCtrlHandler(IntPtr handler, bool add);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GenerateConsoleCtrlEvent(uint ctrlEvent, uint processGroupId);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool FreeConsole();
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool AttachConsole(uint processId);
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll", SetLastError = true)]
public static extern bool PostMessageW(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleScreenBufferInfo(IntPtr output, out BufferInfo info);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool ReadConsoleOutputCharacterW(IntPtr output, System.Text.StringBuilder text, uint length, Coord start, out uint read);

// The text of every row of this process's console, one line each.
public static string[] Screen() {
  IntPtr output = CreateFileW("CONOUT$", 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
  BufferInfo info;
  if (!GetConsoleScreenBufferInfo(output, out info)) throw new System.ComponentModel.Win32Exception();
  var rows = new string[info.Cursor.Y + 1];
  for (short y = 0; y <= info.Cursor.Y; y++) {
    var text = new System.Text.StringBuilder(info.Size.X);
    uint read;
    var start = new Coord { X = 0, Y = y };
    ReadConsoleOutputCharacterW(output, text, (uint)info.Size.X, start, out read);
    rows[y] = text.ToString(0, (int)read).TrimEnd();
  }
  return rows;
}
'@

function Fail([string] $message) {
  Write-Host "::error::Delivery (console): $message"
  exit 1
}

function Expect([string] $Label, $Actual, $Expected) {
  if ($Actual -cne $Expected) { Fail "$Label is '$Actual', not '$Expected'" }
  Write-Host "ok: $Label is $Expected"
}

# Waits up to 30 seconds for $Test to be true.
function Await([scriptblock] $Test) {
  for ($tick = 0; $tick -lt 300; $tick++) {
    if (& $Test) { return $true }
    Start-Sleep -Milliseconds 100
  }
  return $false
}

function Quote([string] $argument) { "`"$argument`"" }

# The program and the arguments before the log, from a state file the
# outer run wrote.
function Read-Command([string] $work) {
  Get-Content -LiteralPath (Join-Path $work 'command.txt') -Encoding utf8
}

# Inside the new console: sets its code page, starts the probe on it with
# a PATH of only Windows' own folders, ends it as the scenario says, and
# writes what happened for the outer run to read.
if ($Inner) {
  $scenario, $codePage = $Inner -split ':'
  [void][Fledge.Console]::SetConsoleCP([uint32]$codePage)
  [void][Fledge.Console]::SetConsoleOutputCP([uint32]$codePage)
  $command = @(Read-Command $Work)
  $log = Join-Path $Work "$scenario-$codePage.log"
  $system = $env:SystemRoot
  $env:PATH = "$system\System32;$system;$system\System32\Wbem"
  $arguments = @($command | Select-Object -Skip 1 | ForEach-Object { Quote $_ }) + (Quote $log)
  $probe = Start-Process -FilePath $command[0] -ArgumentList $arguments -NoNewWindow -PassThru -WorkingDirectory $system
  $null = $probe.Handle
  Set-Content -LiteralPath (Join-Path $Work "$scenario-$codePage.pid") -Value $probe.Id
  if (-not (Await { (Test-Path -LiteralPath $log) -and (Get-Content -LiteralPath $log) -contains 'ready' })) {
    Set-Content -LiteralPath (Join-Path $Work "$scenario-$codePage.result") -Value 'never ready'
    $probe.Kill()
    exit 1
  }
  if ($scenario -eq 'interrupt') {
    # This console's Ctrl-C, ignored by this process, which the probe
    # did not inherit, having started before.
    [void][Fledge.Console]::SetConsoleCtrlHandler([IntPtr]::Zero, $true)
    if (-not [Fledge.Console]::GenerateConsoleCtrlEvent(0, 0)) { throw [ComponentModel.Win32Exception]::new() }
  }
  if (-not $probe.WaitForExit(30000)) {
    Set-Content -LiteralPath (Join-Path $Work "$scenario-$codePage.result") -Value 'did not end'
    $probe.Kill()
    exit 1
  }
  $screen = [Fledge.Console]::Screen()
  Set-Content -LiteralPath (Join-Path $Work "$scenario-$codePage.screen") -Value $screen -Encoding utf8
  Set-Content -LiteralPath (Join-Path $Work "$scenario-$codePage.result") -Value $probe.ExitCode
  exit 0
}

$work = Join-Path $env:RUNNER_TEMP "console-$PID"
New-Item -ItemType Directory -Force $work | Out-Null

if ($Reference) {
  $label = 'ruby.exe main.rb'
  $command = @((Resolve-Path -LiteralPath $Reference[0]).Path, (Resolve-Path -LiteralPath $Reference[1]).Path)
} else {
  $label = 'the built app'
  $Archive = (Resolve-Path -LiteralPath $Archive).Path
  $name = [IO.Path]::GetFileNameWithoutExtension($Archive)
  Expand-Archive -LiteralPath $Archive -DestinationPath (Join-Path $work 'apps')
  $command = @(Join-Path (Join-Path (Join-Path $work 'apps') $name) "$($name -replace '-x64-mingw-ucrt$', '').exe")
}
Set-Content -LiteralPath (Join-Path $work 'command.txt') -Value $command -Encoding utf8

# Runs the probe in a new console, which Start-Process opens for a
# console program, as Explorer does, and returns the inner run's process.
function Start-Inner([string] $scenario, [string] $codePage) {
  $shell = (Get-Process -Id $PID).Path
  Start-Process -FilePath $shell -PassThru -ArgumentList '-NoProfile', '-File', (Quote $PSCommandPath),
    '-Inner', "${scenario}:$codePage", '-Work', (Quote $work)
}

function Record([string] $scenario, [string] $codePage) {
  (Get-Content -LiteralPath (Join-Path $work "$scenario-$codePage.log") -Encoding utf8) -join "`n"
}

foreach ($case in @(@('65001', 'UTF-8'), @('437', 'IBM437'))) {
  $codePage, $encoding = $case
  $inner = Start-Inner 'interrupt' $codePage
  if (-not $inner.WaitForExit(90000)) { Fail "$label's console did not finish (interrupt, code page $codePage)" }
  $result = Get-Content -LiteralPath (Join-Path $work "interrupt-$codePage.result") -ErrorAction SilentlyContinue
  if ($inner.ExitCode -ne 0) { Fail "$label, interrupted on code page ${codePage}: $result" }
  Expect "$label's exit status on Ctrl-C (code page $codePage)" $result '3'
  Expect "what $label recorded on Ctrl-C (code page $codePage)" (Record 'interrupt' $codePage) `
    "external $encoding`nready`nensure ran (Interrupt: )`nat_exit ran"
  $screen = Get-Content -LiteralPath (Join-Path $work "interrupt-$codePage.screen") -Encoding utf8
  Expect "the line $label printed, on the console (code page $codePage)" ($screen | Where-Object { $_ -like 'caf*' } | Select-Object -First 1) "caf$([char]0xE9) $([char]0x2713)"
}

# The console's window closes: the probe's process, attached to it, gets
# CTRL_CLOSE_EVENT from the console host.
$inner = Start-Inner 'close' '65001'
$pidFile = Join-Path $work 'close-65001.pid'
$log = Join-Path $work 'close-65001.log'
if (-not (Await { (Test-Path -LiteralPath $log) -and (Get-Content -LiteralPath $log) -contains 'ready' })) { Fail "$label never got ready (close)" }
$probe = Get-Process -Id ([int](Get-Content -LiteralPath $pidFile))
$null = $probe.Handle
[void][Fledge.Console]::FreeConsole()
if (-not [Fledge.Console]::AttachConsole([uint32]$probe.Id)) { Fail "could not attach to $label's console: $([ComponentModel.Win32Exception]::new().Message)" }
$window = [Fledge.Console]::GetConsoleWindow()
[void][Fledge.Console]::FreeConsole()
if ($window -eq [IntPtr]::Zero) { Fail "$label's console has no window to close" }
if (-not [Fledge.Console]::PostMessageW($window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)) { Fail 'could not close the console window' }
if (-not $probe.WaitForExit(30000)) { Fail "$label did not end when its console closed" }
Expect "$label's exit status when its console closed" ('0x{0:X8}' -f $probe.ExitCode) '0xC000013A'
Expect "what $label recorded when its console closed" (Record 'close' '65001') "external UTF-8`nready"
$null = $inner.WaitForExit(30000)

# A windowed app, typed into a console: PowerShell starts it and goes
# on, as it does rubyw.exe, and the app has no console.
if ($WindowedReference) {
  $windowedLabel = 'rubyw.exe main.rb'
  $windowed = @((Resolve-Path -LiteralPath $WindowedReference[0]).Path, (Resolve-Path -LiteralPath $WindowedReference[1]).Path)
} elseif ($Windowed) {
  $windowedLabel = 'the built windowed app'
  $Windowed = (Resolve-Path -LiteralPath $Windowed).Path
  $name = [IO.Path]::GetFileNameWithoutExtension($Windowed)
  Expand-Archive -LiteralPath $Windowed -DestinationPath (Join-Path $work 'windowed')
  $windowed = @(Join-Path (Join-Path (Join-Path $work 'windowed') $name) "$($name -replace '-x64-mingw-ucrt$', '').exe")
}
if ($Windowed -or $WindowedReference) {
  $report = Join-Path $work 'windowed report.json'
  $clock = [Diagnostics.Stopwatch]::StartNew()
  & $windowed[0] @($windowed | Select-Object -Skip 1) $report 4
  $returned = $clock.Elapsed.TotalSeconds
  if ($returned -ge 1.5) { Fail "the console waited $returned seconds for $windowedLabel, which lives for 2" }
  Write-Host "ok: the console went on after $([math]::Round($returned, 2)) seconds"
  if (-not (Await { Test-Path -LiteralPath $report })) { Fail "$windowedLabel never wrote its report" }
  Start-Sleep -Seconds 3
  $facts = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
  Expect "whether $windowedLabel had a console" $facts.console $false
}

Write-Host "Delivered: the console's Ctrl-C, code pages, and closing end $label as they end ruby.exe"
