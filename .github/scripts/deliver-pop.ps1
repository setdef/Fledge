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
#   pwsh -NoProfile -File deliver-pop.ps1 -Archive ARCHIVE [-Mesa FOLDER] [-Work FOLDER]
#
# ARCHIVE is "Pop-x64-mingw-ucrt.zip", or aarch64-mingw-ucrt's. The
# clicks are the messages a mouse sends (WM_MOUSEMOVE, WM_LBUTTONDOWN,
# WM_LBUTTONUP), posted to the window, which needs no desktop that takes
# input. Pop is a GUI program, so its output is its standard output
# redirected to a file. WORK is the one folder the script writes in:
# RUNNER_TEMP on a runner, and the system's temporary folder elsewhere.
#
# A runner has no GPU, so Pop draws with OpenGL, not Vulkan, and the
# opengl32.dll in System32 gives OpenGL 1.1, which Lota's renderer cannot
# use, so Pop's window stays 0x0 and its loop never runs. MESA is a
# folder holding Mesa's opengl32.dll, its driver, and the DLLs they need
# (ci.yml's x64 step copies four from mesa-dist-win; gather-mesa.sh gathers
# ARM64's). The script puts those beside Pop.exe, where Windows finds the
# opengl32.dll SDL3 loads by name before System32's, and asks Mesa for
# llvmpipe, its software renderer, as Lota's CI does for the games it
# delivers. The app's files, its Ruby, and its code are as Fledge built
# them.

param(
  [Parameter(Mandatory)] [string] $Archive,
  [string] $Mesa,
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
if ($Mesa) {
  foreach ($dll in Get-ChildItem -LiteralPath $Mesa -Filter '*.dll') {
    $beside = Join-Path (Split-Path $app) $dll.Name
    if (Test-Path -LiteralPath $beside) { Write-Host "$($dll.Name): already beside Pop.exe" } else { Copy-Item -LiteralPath $dll.FullName $beside }
  }
  if (-not (Test-Path -LiteralPath (Join-Path (Split-Path $app) 'opengl32.dll'))) { Fail "$Mesa holds no opengl32.dll" }
  $env:GALLIUM_DRIVER = 'llvmpipe'
  # llvmpipe's linear rasterizer, from Mesa 25, reads the wrong uniform
  # array and matrix elements; Lota's CI turns it off.
  $env:LP_PERF = 'no_rast_linear'
}

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
# SDL sizes the window after it shows it, so the client area is read
# until it has one.
$rect = New-Object Fledge.Pop+RECT
do {
  [void] [Fledge.Pop]::GetClientRect($window, [ref] $rect)
  if ($rect.Right -gt 0) { break }
  if ($process.HasExited) { Fail "Pop ended before its window had a client area`n$(Show-Log)" }
  Start-Sleep -Milliseconds 200
} while ([DateTime]::UtcNow -lt $deadline)
if ($rect.Right -le 0 -or $rect.Bottom -le 0) { Fail "Pop's window is $($rect.Right)x$($rect.Bottom) 30 seconds after the start`n$(Show-Log)" }
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
# Pop reports each dot that appears on standard error, as "Pop: 3 dots,
# 0 popped" (examples/lota_pop/game/main.rb); anything else is a fault.
$errors = ((Get-Content -LiteralPath $err -Raw) -replace '\s+$', '')
$other = @($errors -split '\r?\n' | Where-Object { $_ -ne '' -and $_ -notmatch '^Pop: \d+ dots?, \d+ popped$' })
if ($other.Count -gt 0) { Fail "Pop wrote to standard error: $($other -join '; ')" }
Write-Host 'Delivered: Pop popped a dot and ended cleanly, on Windows'
