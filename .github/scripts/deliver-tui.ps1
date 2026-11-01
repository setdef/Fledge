# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Delivery of a terminal UI built with Fledge, on Windows: runs the built
# app's program in a console of its own, with a PATH that holds only
# Windows' folders and a Ruby's settings in the environment that the app
# must not see, waits for the app's first screen in the console's
# screen buffer, types 'a' and sees the screen change, types Ctrl-C (as a
# key, since a terminal UI turns off the console's processing of it) and
# expects the app to exit with status 0.
#
#   deliver-tui.ps1 -Archive RooibosApp-x64-mingw-ucrt.zip
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
  Write-Host "::error::Delivery (terminal UI): $message"
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

if ($Inner) {
  trap {
    Set-Content -LiteralPath (Join-Path $Work 'result') -Value "failed: $_"
    exit 1
  }
  $system = $env:SystemRoot
  $env:PATH = "$system\System32;$system;$system\System32\Wbem"
  $env:RUBYOPT = '-rnonexistent_library_a_person_set'
  $env:RUBYLIB = $Work
  $env:GEM_HOME = Join-Path $Work 'gems'
  $program = (Get-Content -LiteralPath (Join-Path $Work 'program.txt') -Encoding utf8)
  $app = Start-Process -FilePath $program -NoNewWindow -PassThru -WorkingDirectory $system
  $null = $app.Handle
  if (-not (Await { Screen-Has 'Current\s*count:\s*0\.' })) {
    Set-Content -LiteralPath (Join-Path $Work 'result') -Value ("never showed its first screen:`n" + (([Fledge.Tui]::Screen()) -join "`n"))
    $app.Kill()
    exit 1
  }
  Set-Content -LiteralPath (Join-Path $Work 'first') -Value 'ok'
  [Fledge.Tui]::Key(0x41, [uint16][char]'a', 0)
  if (-not (Await { Screen-Has 'Current\s*count:\s*1\.' } 300)) {
    Set-Content -LiteralPath (Join-Path $Work 'result') -Value ("a key did not change the screen:`n" + (([Fledge.Tui]::Screen()) -join "`n"))
    $app.Kill()
    exit 1
  }
  Set-Content -LiteralPath (Join-Path $Work 'second') -Value 'ok'
  # Ctrl-C as a key: virtual key C, character 3, left Ctrl held.
  [Fledge.Tui]::Key(0x43, 3, 0x8)
  if (-not $app.WaitForExit(30000)) {
    Set-Content -LiteralPath (Join-Path $Work 'result') -Value 'Ctrl-C did not end the app'
    $app.Kill()
    exit 1
  }
  Set-Content -LiteralPath (Join-Path $Work 'result') -Value $app.ExitCode
  exit 0
}

$work = Join-Path $env:RUNNER_TEMP "tui-$PID"
New-Item -ItemType Directory -Force $work | Out-Null
$Archive = (Resolve-Path -LiteralPath $Archive).Path
$name = [IO.Path]::GetFileNameWithoutExtension($Archive)
Expand-Archive -LiteralPath $Archive -DestinationPath (Join-Path $work 'apps')
$program = Join-Path (Join-Path (Join-Path $work 'apps') $name) "$($name -replace '-(?:x64|aarch64)-mingw-ucrt$', '').exe"
Set-Content -LiteralPath (Join-Path $work 'program.txt') -Value $program -Encoding utf8

$shell = (Get-Process -Id $PID).Path
$console = Start-Process -FilePath $shell -PassThru -ArgumentList '-NoProfile', '-File', (Quote $PSCommandPath), '-Inner', 'run', '-Work', (Quote $work)
if (-not $console.WaitForExit(180000)) { Fail "the console did not finish" }
$result = Get-Content -LiteralPath (Join-Path $work 'result') -ErrorAction SilentlyContinue
if ($console.ExitCode -ne 0) { Fail "the app in its console: $result" }
if (-not (Test-Path (Join-Path $work 'first'))) { Fail 'no first screen' }
Write-Host "ok: the first screen shows 'Current count: 0.'"
if (-not (Test-Path (Join-Path $work 'second'))) { Fail 'no second screen' }
Write-Host "ok: a key typed into the console changed the screen to count 1"
if ($result -ne '0') { Fail "the app exited with status $result, not 0" }
Write-Host "ok: Ctrl-C ended the app with status 0"
