# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of Basket, the shopping list of examples/basket, on Windows:
# unpacks what fledge build wrote, starts Basket.exe as Explorer would,
# with no Ruby anywhere it can reach, and does what a person does at its
# window: types an item, presses Return, selects the row, and presses
# Remove. Basket must show its list in Common Controls 6, draw per
# monitor at the monitor's scale, and log "Basket added Milk" and
# "Basket removed Milk".
#
#   pwsh -NoProfile -File check-basket-window.ps1 -Archive ARCHIVE [-Work FOLDER]
#
# ARCHIVE is "Basket-x64-mingw-ucrt.zip", or aarch64-mingw-ucrt's. The
# script reaches the window the way any program does, by posting the
# messages that typing and clicking send (WM_CHAR, WM_KEYDOWN, BM_CLICK),
# which needs no desktop that takes input, and it reads the list's rows
# with LVM_GETITEMCOUNT, which Windows answers for another process. Basket
# is a GUI program, so its log is its standard output redirected to a file.
# WORK is the one folder the script writes in: RUNNER_TEMP on a runner,
# and the system's temporary folder elsewhere.
#
# The script runs Basket with BASKET_SCREEN=win32, which makes it draw its
# Win32 screen whatever the runner holds. Basket draws WinUI 3's screen instead
# on a Windows that has the Windows App Runtime registered, and a runner
# image may or may not have it, so without the setting this job would
# check one screen on one image and the other on the next. Everything
# above is of Win32's controls (the BasketWindow class, comctl32.dll,
# SysListView32, and messages a WinUI window ignores), so the setting keeps
# the job's proof the same on every runner: that the built app, with no
# Ruby, draws the screen that a Windows without the runtime gets. WinUI's
# screen is not checked here; its tests (examples/basket/test/winui_test.rb)
# run on a Windows that has the runtime.

param(
  [Parameter(Mandatory)] [string] $Archive,
  [string] $Work = $(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

function Fail([string] $message) {
  Write-Host "::error::Delivery (Basket): $message"
  exit 1
}

function Expect([string] $Label, $Actual, $Expected) {
  if ($Actual -cne $Expected) { Fail "$Label is '$Actual', not '$Expected'" }
  Write-Host "ok: $Label is $Expected"
}

Add-Type -Namespace Fledge -Name Basket -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr FindWindowExW(IntPtr parent, IntPtr after, string windowClass, string title);
[DllImport("user32.dll")]
public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
[DllImport("user32.dll")]
public static extern bool PostMessageW(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam);
[DllImport("user32.dll")]
public static extern IntPtr SendMessageW(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam);
[DllImport("user32.dll")]
public static extern IntPtr GetWindowDpiAwarenessContext(IntPtr window);
[DllImport("user32.dll")]
public static extern int GetAwarenessFromDpiAwarenessContext(IntPtr context);
'@

$WM_CLOSE = 0x10; $WM_GETTEXTLENGTH = 0x0E; $WM_KEYDOWN = 0x100; $WM_CHAR = 0x102
$BM_CLICK = 0xF5; $LVM_GETITEMCOUNT = 0x1004
$VK_RETURN = 0x0D; $VK_DOWN = 0x28

function Post([IntPtr] $Window, [uint32] $Message, [uint64] $WParam = 0) {
  if (-not [Fledge.Basket]::PostMessageW($Window, $Message, [UIntPtr]::new($WParam), [IntPtr]::Zero)) { Fail "PostMessage $Message failed" }
}

function Ask([IntPtr] $Window, [uint32] $Message) {
  [Fledge.Basket]::SendMessageW($Window, $Message, [UIntPtr]::Zero, [IntPtr]::Zero).ToInt64()
}

# Waits up to 30 seconds for the block to say yes.
function WaitFor([string] $What, [scriptblock] $Block) {
  $deadline = [DateTime]::UtcNow.AddSeconds(30)
  while (-not (& $Block)) {
    if ([DateTime]::UtcNow -gt $deadline) { Fail "Basket did not $What within 30 seconds`n$(Show-Log)" }
    Start-Sleep -Milliseconds 100
  }
}

function Show-Log {
  foreach ($file in $out, $err) { if (Test-Path -LiteralPath $file) { "$file`: $(Get-Content -LiteralPath $file -Raw)" } }
}

$Archive = (Resolve-Path -LiteralPath $Archive).Path
$name = [IO.Path]::GetFileNameWithoutExtension($Archive)
$place = Join-Path (Join-Path $Work 'Fledge Basket') "b$([char]0xE4)sket"
New-Item -ItemType Directory -Force $place | Out-Null
Expand-Archive -LiteralPath $Archive -DestinationPath $place
$app = Join-Path (Join-Path $place $name) 'Basket.exe'
if (-not (Test-Path -LiteralPath $app -PathType Leaf)) { Fail "$app is missing after unpacking $Archive" }

# The runner has Rubies; the app's PATH keeps only the system's folders.
# Its list is basket.json in setdef\Basket\data under the Roaming AppData
# folder, which Basket takes from %APPDATA% when that is set, and which
# starts empty.
$system = $env:SystemRoot
$env:PATH = "$system\System32;$system;$system\System32\Wbem;$system\System32\WindowsPowerShell\v1.0"
if (Get-Command ruby -ErrorAction SilentlyContinue) { Fail "Get-Command still finds a Ruby on $env:PATH" }
$home_folder = Join-Path $Work 'Basket home'
New-Item -ItemType Directory -Force $home_folder | Out-Null
$env:BASKET_SCREEN = 'win32'
$env:HOME = $home_folder
$env:USERPROFILE = $home_folder
$env:APPDATA = Join-Path $Work 'Basket app data'
$list = Join-Path $env:APPDATA 'setdef\Basket\data\basket.json'
Remove-Item -LiteralPath $env:APPDATA -Recurse -ErrorAction SilentlyContinue
$out = Join-Path $Work 'basket.out'
$err = Join-Path $Work 'basket.err'
Remove-Item -LiteralPath $out, $err -ErrorAction SilentlyContinue

$process = Start-Process -FilePath $app -WorkingDirectory $system -PassThru `
  -RedirectStandardOutput $out -RedirectStandardError $err
# PowerShell reads ExitCode as empty, for a process that was not waited on
# with -Wait, unless something has asked for the process's handle first.
$null = $process.Handle
# Windows can put windows in a GUI process (the text services' and the UAC
# indicator's), and .NET may call one of them the process's main window, so
# Basket's window is the process's top-level window of Basket's class, which
# is there once its controls are, and each control is looked for in it.
WaitFor 'show a window with a text field, a list, and a Remove button' {
  $script:window = [IntPtr]::Zero
  $found = [IntPtr]::Zero
  while (($found = [Fledge.Basket]::FindWindowExW([IntPtr]::Zero, $found, 'BasketWindow', [NullString]::Value)) -ne [IntPtr]::Zero) {
    [uint32] $owner = 0
    [void] [Fledge.Basket]::GetWindowThreadProcessId($found, [ref] $owner)
    if ($owner -eq $process.Id) { $script:window = $found; break }
  }
  if ($script:window -eq [IntPtr]::Zero) { return $false }
  $script:field = [Fledge.Basket]::FindWindowExW($script:window, [IntPtr]::Zero, 'Edit', [NullString]::Value)
  $script:list = [Fledge.Basket]::FindWindowExW($script:window, [IntPtr]::Zero, 'SysListView32', [NullString]::Value)
  $script:remove = [Fledge.Basket]::FindWindowExW($script:window, [IntPtr]::Zero, 'Button', 'Remove')
  ($script:field -ne [IntPtr]::Zero) -and ($script:list -ne [IntPtr]::Zero) -and ($script:remove -ne [IntPtr]::Zero)
}
$window = $script:window; $field = $script:field; $list = $script:list; $remove = $script:remove
Write-Host 'ok: the window has a text field, a list, and a Remove button'

# Common Controls 6 is loaded from WinSxS, which the assembly's version in
# the file's path says (the file's version string says 5.82 in both
# versions), and the window is per monitor aware (DPI_AWARENESS_PER_MONITOR_AWARE
# is 2): Basket's Ruby asked for both.
$controls = @($process.Modules | Where-Object { $_.ModuleName -eq 'COMCTL32.DLL' })
if ($controls.Count -ne 1) { Fail "the process holds $($controls.Count) comctl32.dll modules" }
if ($controls[0].FileName -notmatch 'common-controls_6595b64144ccf1df_6\.') { Fail "comctl32.dll is $($controls[0].FileName), not Common Controls 6" }
Write-Host "ok: the controls are Common Controls 6, from $($controls[0].FileName)"
Expect "the window's DPI awareness" ([Fledge.Basket]::GetAwarenessFromDpiAwarenessContext([Fledge.Basket]::GetWindowDpiAwarenessContext($window))) 2

Expect 'the rows at the start' (Ask $list $LVM_GETITEMCOUNT) 0
foreach ($character in 'Milk'.ToCharArray()) { Post $field $WM_CHAR ([uint64] $character) }
Post $field $WM_KEYDOWN $VK_RETURN
WaitFor 'add a row when Return was pressed' { (Ask $list $LVM_GETITEMCOUNT) -eq 1 }
Expect 'the rows after Return' (Ask $list $LVM_GETITEMCOUNT) 1
WaitFor 'empty the field' { (Ask $field $WM_GETTEXTLENGTH) -eq 0 }
Write-Host 'ok: the field is empty'

# Down in the list selects its first row; Remove takes the selected row.
Post $list $WM_KEYDOWN $VK_DOWN
Post $remove $BM_CLICK
WaitFor 'remove the row when Remove was pressed' { (Ask $list $LVM_GETITEMCOUNT) -eq 0 }
Write-Host 'ok: Remove took the row away'

Post $window $WM_CLOSE
if (-not $process.WaitForExit(30000)) { Fail "Basket did not exit when its window was closed`n$(Show-Log)" }
Expect 'the exit status' $process.ExitCode 0
$lines = @(Get-Content -LiteralPath $out)
# Basket logs its list's path with the slashes Ruby's Pathname joins it
# with, which Windows reads as the same path.
Expect 'where Basket said it keeps its list' ($lines[0] -replace '/', '\') "Basket keeps its list in $list"
Expect 'what Basket logged after that' ($lines[1..($lines.Count - 1)] -join '|') 'Basket shows 0 items|Basket added Milk|Basket removed Milk'
Expect 'what Basket saved in its list' ((Get-Content -LiteralPath $list -Raw) -replace '\s+$', '') '[]'
Expect 'what Basket wrote to standard error' ((Get-Content -LiteralPath $err -Raw) -replace '\s+$', '') ''

Write-Host 'Delivered: Basket, on Windows'
