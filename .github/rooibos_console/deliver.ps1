# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Runs the Fledge Check app in a console of its own, on Windows, with a
# PATH that holds only Windows' folders and a Ruby's settings in the
# environment. The screen buffer must show the facts, the frame counter
# must advance, a key must show, r must write the report in the current
# folder, and q must end the app with status 0. A second run is ended with
# Ctrl-C and its status is only reported.
#
#   deliver.ps1 -Archive "Fledge Check-x64-mingw-ucrt.zip"
#
# -Inner is how the script runs itself in a new console.


param(
  [string] $Archive,
  [string] $Inner,
  [string] $Work
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -Namespace Fledge -Name Tui -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct Coord { public short X; public short Y; }
[StructLayout(LayoutKind.Sequential)]
public struct Rect { public short Left; public short Top; public short Right; public short Bottom; }
[StructLayout(LayoutKind.Sequential)]
public struct BufferInfo { public Coord Size; public Coord Cursor; public ushort Attributes; public Rect Window; public Coord MaximumWindow; }
[StructLayout(LayoutKind.Explicit)]
public struct InputRecord {
  [FieldOffset(0)] public ushort EventType;
  [FieldOffset(4)] public int KeyDown;
  [FieldOffset(8)] public ushort Repeat;
  [FieldOffset(10)] public ushort VirtualKey;
  [FieldOffset(12)] public ushort ScanCode;
  [FieldOffset(14)] public ushort Char;
  [FieldOffset(16)] public uint ControlKeys;
}

[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleScreenBufferInfo(IntPtr output, out BufferInfo info);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool ReadConsoleOutputCharacterW(IntPtr output, System.Text.StringBuilder text, uint length, Coord start, out uint read);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool WriteConsoleInputW(IntPtr input, InputRecord[] records, uint length, out uint written);

// The text of every row of the console's active screen buffer.
public static string[] Screen() {
  IntPtr output = CreateFileW("CONOUT$", 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
  BufferInfo info;
  if (!GetConsoleScreenBufferInfo(output, out info)) throw new System.ComponentModel.Win32Exception();
  var rows = new string[info.Window.Bottom + 1];
  for (short y = 0; y <= info.Window.Bottom; y++) {
    var text = new System.Text.StringBuilder(info.Size.X);
    uint read;
    var start = new Coord { X = 0, Y = y };
    ReadConsoleOutputCharacterW(output, text, (uint)info.Size.X, start, out read);
    rows[y] = text.ToString(0, (int)read).TrimEnd();
  }
  return rows;
}

// Types one key into the console, down and up.
public static void Key(ushort virtualKey, ushort character, uint controlKeys) {
  IntPtr input = CreateFileW("CONIN$", 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
  var records = new InputRecord[2];
  for (int i = 0; i < 2; i++) {
    records[i] = new InputRecord { EventType = 1, KeyDown = (i == 0) ? 1 : 0, Repeat = 1, VirtualKey = virtualKey, ScanCode = 0, Char = character, ControlKeys = controlKeys };
  }
  uint written;
  if (!WriteConsoleInputW(input, records, 2, out written)) throw new System.ComponentModel.Win32Exception();
}
'@

function Fail([string] $message) {
  Write-Host "::error::Fledge Check: $message"
  exit 1
}

function Await([scriptblock] $Test, [int] $Ticks = 600) {
  for ($tick = 0; $tick -lt $Ticks; $tick++) {
    if (& $Test) { return $true }
    Start-Sleep -Milliseconds 100
  }
  return $false
}

function Quote([string] $argument) { "`"$argument`"" }

function Screen-Has([string] $pattern) {
  $text = ([Fledge.Tui]::Screen()) -join "`n"
  $text -match $pattern
}


function Dump { ([Fledge.Tui]::Screen()) -join "`n" }
function Out-Result([string] $text) { Set-Content -LiteralPath (Join-Path $Work 'result') -Value $text }

if ($Inner) {
  trap {
    Out-Result "failed: $_"
    exit 1
  }
  $system = $env:SystemRoot
  $env:PATH = "$system\System32;$system;$system\System32\Wbem"
  $env:RUBYOPT = '-rnonexistent_library_a_person_set'
  $env:RUBYLIB = $Work
  $env:GEM_HOME = Join-Path $Work 'gems'
  $program = (Get-Content -LiteralPath (Join-Path $Work 'program.txt') -Encoding utf8)
  $app = Start-Process -FilePath $program -NoNewWindow -PassThru -WorkingDirectory $Work
  $null = $app.Handle
  $facts = 'Fledge\s*app:\s*yes', 'Operating\s*system', 'Processor', 'RbConfig\.ruby', 'Gem\.dir', 'Clock\s*\d\d:\d\d:\d\d'
  if (-not (Await { $text = Dump; -not ($facts | Where-Object { $text -notmatch $_ }) })) {
    Out-Result ("the screen lacks some of the facts:`n" + (Dump))
    $app.Kill(); exit 1
  }
  Set-Content -LiteralPath (Join-Path $Work 'facts') -Value (Dump)
  $first = [regex]::Match((Dump), 'frame\s*(\d+)').Groups[1].Value
  Start-Sleep -Seconds 2
  $later = [regex]::Match((Dump), 'frame\s*(\d+)').Groups[1].Value
  if (-not $first -or -not $later -or [int]$later -le [int]$first) {
    Out-Result "the frame counter did not advance: '$first' then '$later'"
    $app.Kill(); exit 1
  }
  Set-Content -LiteralPath (Join-Path $Work 'frames') -Value "$first then $later"
  [Fledge.Tui]::Key(0x57, [uint16][char]'w', 0)
  if (-not (Await { (Dump) -match 'Last\s*key\s*w\b' } 300)) {
    Out-Result ("the last key did not show:`n" + (Dump))
    $app.Kill(); exit 1
  }
  Set-Content -LiteralPath (Join-Path $Work 'key') -Value 'ok'
  [Fledge.Tui]::Key(0x52, [uint16][char]'r', 0)
  if (-not (Await { Test-Path -LiteralPath (Join-Path $Work 'fledge-check-report.txt') } 300)) {
    Out-Result ("r wrote no report:`n" + (Dump))
    $app.Kill(); exit 1
  }
  [Fledge.Tui]::Key(0x51, [uint16][char]'q', 0)
  if (-not $app.WaitForExit(30000)) {
    Out-Result 'q did not end the app'
    $app.Kill(); exit 1
  }
  Out-Result $app.ExitCode
  # A second run, ended with Ctrl-C (virtual key C, character 3, left Ctrl held).
  $again = Start-Process -FilePath $program -NoNewWindow -PassThru -WorkingDirectory $Work
  $null = $again.Handle
  if (Await { (Dump) -match 'Gem\.dir' }) {
    [Fledge.Tui]::Key(0x43, 3, 0x8)
    if ($again.WaitForExit(30000)) {
      Set-Content -LiteralPath (Join-Path $Work 'interrupt') -Value $again.ExitCode
    } else {
      $again.Kill()
    }
  } else {
    $again.Kill()
  }
  exit 0
}

$work = Join-Path $env:RUNNER_TEMP "check-$PID"
New-Item -ItemType Directory -Force $work | Out-Null
$Archive = (Resolve-Path -LiteralPath $Archive).Path
$name = [IO.Path]::GetFileNameWithoutExtension($Archive)
Expand-Archive -LiteralPath $Archive -DestinationPath (Join-Path $work 'apps')
$program = Join-Path (Join-Path (Join-Path $work 'apps') $name) "$($name -replace '-(?:x64|aarch64)-mingw-ucrt$', '').exe"
Set-Content -LiteralPath (Join-Path $work 'program.txt') -Value $program -Encoding utf8

$shell = (Get-Process -Id $PID).Path
$console = Start-Process -FilePath $shell -PassThru -ArgumentList '-NoProfile', '-File', (Quote $PSCommandPath), '-Inner', 'run', '-Work', (Quote $work)
if (-not $console.WaitForExit(240000)) { Fail 'the console did not finish' }
$Work = $work
$result = Get-Content -LiteralPath (Join-Path $work 'result') -ErrorAction SilentlyContinue
if ($console.ExitCode -ne 0) { Fail "the app in its console: $result" }
Write-Host 'the screen:'
Get-Content -LiteralPath (Join-Path $work 'facts')
Write-Host 'ok: the screen shows the facts'
Write-Host "ok: the frame counter advanced: $(Get-Content -LiteralPath (Join-Path $work 'frames'))"
Write-Host 'ok: the last key typed shows on the screen'
$report = Join-Path $work 'fledge-check-report.txt'
$body = Get-Content -LiteralPath $report -Raw
if ($body -notmatch 'Fledge app: yes' -or $body -notmatch 'RUBYOPT') { Fail "the report lacks the facts: $body" }
Write-Host 'ok: r wrote the report:'
Write-Host $body
if ($result -ne '0') { Fail "q ended the app with status $result, not 0" }
Write-Host 'ok: q ended the app with status 0'
$interrupt = Join-Path $work 'interrupt'
if (Test-Path $interrupt) { Write-Host "info: Ctrl-C ended the app with status $(Get-Content -LiteralPath $interrupt)" } else { Write-Host 'info: Ctrl-C did not end the second run' }
