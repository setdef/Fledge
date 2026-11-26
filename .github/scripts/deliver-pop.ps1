# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of Pop, the Lota game of examples/lota_pop, on Windows:
# unpacks what fledge build wrote, starts Pop.exe as Explorer would, with
# no Ruby anywhere it can reach, and clicks in its window as a person
# does. Pop prints its score and quits when POP_QUIT_AFTER seconds have
# passed (examples/lota_pop/game/main.rb), so the script lets the dots
# appear, clicks the window every 48 pixels, which lies within a dot's
# radius of each dot, and fails unless Pop ends by itself with status 0
# and prints "Pop: N popped" with N of 1 or more. That says that Lota
# opened a window through the app's own Ruby and SDL3, drew frames, took
# mouse messages for clicks, popped a dot, and ended the game and the
# process cleanly.
#
#   pwsh -NoProfile -File deliver-pop.ps1 -Archive ARCHIVE [-Work FOLDER]
#
# ARCHIVE is "Pop-x64-mingw-ucrt.zip", or aarch64-mingw-ucrt's. The
# clicks are the messages a mouse sends (WM_MOUSEMOVE, WM_LBUTTONDOWN,
# WM_LBUTTONUP), posted to the window, which needs no desktop that takes
# input. Pop is a GUI program, so its output is its standard output
# redirected to a file. WORK is the one folder the script writes in:
# RUNNER_TEMP on a runner, and the system's temporary folder elsewhere.

param(
  [Parameter(Mandatory)] [string] $Archive,
  [string] $Work = $(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Fail([string] $message) {
  Write-Host "::error::Delivery (Pop): $message"
  exit 1
}

Add-Type -Namespace Fledge -Name Pop -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr FindWindowExW(IntPtr parent, IntPtr after, string windowClass, string title);
[DllImport("user32.dll")]
public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
[DllImport("user32.dll")]
public static extern bool PostMessageW(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam);
[DllImport("user32.dll")]
public static extern bool GetClientRect(IntPtr window, out RECT rect);
public struct RECT { public int Left, Top, Right, Bottom; }
'@

$WM_MOUSEMOVE = 0x200; $WM_LBUTTONDOWN = 0x201; $WM_LBUTTONUP = 0x202; $MK_LBUTTON = 1

function Show-Log {
  foreach ($file in $out, $err) { if (Test-Path -LiteralPath $file) { "$file`: $(Get-Content -LiteralPath $file -Raw)" } }
}

# A mouse message at (x, y) of the window's client area.
function Mouse([IntPtr] $Window, [uint32] $Message, [uint64] $WParam, [int] $X, [int] $Y) {
  $lParam = [IntPtr]((($Y -band 0xFFFF) -shl 16) -bor ($X -band 0xFFFF))
  if (-not [Fledge.Pop]::PostMessageW($Window, $Message, [UIntPtr]::new($WParam), $lParam)) { Fail "PostMessage $Message failed" }
}

$Archive = (Resolve-Path -LiteralPath $Archive).Path
$name = [IO.Path]::GetFileNameWithoutExtension($Archive)
$place = Join-Path (Join-Path $Work 'Fledge Pop') "p$([char]0xF6)p"
New-Item -ItemType Directory -Force $place | Out-Null
Expand-Archive -LiteralPath $Archive -DestinationPath $place
$app = Join-Path (Join-Path $place $name) 'Pop.exe'
if (-not (Test-Path -LiteralPath $app -PathType Leaf)) { Fail "$app is missing after unpacking $Archive" }

# The runner has Rubies; the app's PATH keeps only the system's folders.
$system = $env:SystemRoot
$env:PATH = "$system\System32;$system;$system\System32\Wbem;$system\System32\WindowsPowerShell\v1.0"
if (Get-Command ruby -ErrorAction SilentlyContinue) { Fail "Get-Command still finds a Ruby on $env:PATH" }
$home_folder = Join-Path $Work 'Pop home'
New-Item -ItemType Directory -Force $home_folder | Out-Null
$env:HOME = $home_folder
$env:USERPROFILE = $home_folder
$env:POP_QUIT_AFTER = '12'
$out = Join-Path $Work 'pop.out'
$err = Join-Path $Work 'pop.err'
Remove-Item -LiteralPath $out, $err -ErrorAction SilentlyContinue

$process = Start-Process -FilePath $app -WorkingDirectory $system -PassThru `
  -RedirectStandardOutput $out -RedirectStandardError $err
# PowerShell reads ExitCode as empty, for a process that was not waited on
# with -Wait, unless something has asked for the process's handle first.
$null = $process.Handle

# The process's top-level window titled Pop: Windows can put other
# windows in a GUI process.
$window = [IntPtr]::Zero
$deadline = [DateTime]::UtcNow.AddSeconds(30)
while ($window -eq [IntPtr]::Zero) {
  $found = [IntPtr]::Zero
  while (($found = [Fledge.Pop]::FindWindowExW([IntPtr]::Zero, $found, [NullString]::Value, 'Pop')) -ne [IntPtr]::Zero) {
    [uint32] $owner = 0
    [void] [Fledge.Pop]::GetWindowThreadProcessId($found, [ref] $owner)
    if ($owner -eq $process.Id) { $window = $found; break }
  }
  if ($window -ne [IntPtr]::Zero) { break }
  if ($process.HasExited) { Fail "Pop ended before it showed a window`n$(Show-Log)" }
  if ([DateTime]::UtcNow -gt $deadline) { Fail "Pop showed no window titled Pop in 30 seconds`n$(Show-Log)" }
  Start-Sleep -Milliseconds 200
}
$rect = New-Object Fledge.Pop+RECT
[void] [Fledge.Pop]::GetClientRect($window, [ref] $rect)
Write-Host "ok: Pop's window is $($rect.Right)x$($rect.Bottom)"

# A dot appears each second, up to five: after six, there are five.
Start-Sleep -Seconds 6
for ($y = 24; $y -lt $rect.Bottom; $y += 48) {
  for ($x = 24; $x -lt $rect.Right; $x += 48) {
    Mouse $window $WM_MOUSEMOVE 0 $x $y
    Mouse $window $WM_LBUTTONDOWN $MK_LBUTTON $x $y
    Mouse $window $WM_LBUTTONUP 0 $x $y
  }
}
Write-Host 'ok: the sweep clicked the window'

if (-not $process.WaitForExit(60000)) { $process.Kill(); Fail "Pop had not ended 60 seconds after the sweep`n$(Show-Log)" }
if ($process.ExitCode -ne 0) { Fail "Pop exited with $($process.ExitCode)`n$(Show-Log)" }
$line = ((Get-Content -LiteralPath $out -Raw) -replace '\s+$', '')
if ($line -notmatch '^Pop: (\d+) popped$') { Fail "Pop printed '$line', not 'Pop: N popped'`n$(Show-Log)" }
if ([int] $Matches[1] -lt 1) { Fail "Pop printed '$line' after the sweep, which popped no dot" }
Write-Host "ok: Pop ended with status 0 and printed '$line'"
$errors = ((Get-Content -LiteralPath $err -Raw) -replace '\s+$', '')
if ($errors -ne '') { Fail "Pop wrote to standard error: $errors" }
Write-Host 'Delivered: Pop popped a dot and ended cleanly, on Windows'
