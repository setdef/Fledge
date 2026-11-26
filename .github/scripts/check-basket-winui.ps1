# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of Basket's WinUI 3 screen on Windows: registers the Windows App
# Runtime for the account when it is not, unpacks what fledge build wrote,
# starts Basket.exe as Explorer would, with no Ruby anywhere it can reach
# and no BASKET_SCREEN, and does what a person does at its window: types an
# item, presses Add, types another and presses Return, selects a row, and
# presses Remove. Basket must draw WinUI's window, show the rows as it
# does so, and log "Basket added Eggs", "Basket added Milk", and "Basket
# removed Eggs". It then starts Basket again, and ends it by running
# ExitProcess on a thread that it makes in Basket (CreateRemoteThread), as
# Windows ends a process from a thread it made, say for Ctrl+Break at a
# console. Windows then releases Basket's COM objects on that thread, which
# Ruby did not make. The check fails unless Basket exits with the status the
# thread gave and its standard error holds no "[BUG]", which CRuby prints
# when a Ruby callback runs on a thread Ruby did not make (see AddRef and
# Release in lib/basket/winrt.rb).
#
#   powershell -NoProfile -File check-basket-winui.ps1 -Archive ARCHIVE -Platform PLATFORM [-Work FOLDER]
#
# ARCHIVE is "Basket-x64-mingw-ucrt.zip", or aarch64-mingw-ucrt's, and
# PLATFORM is the platform's name. It runs in Windows PowerShell, which has
# .NET's UI Automation client (PowerShell 7 does not). WORK is the one
# folder the script writes in, apart from the account's package
# registration: RUNNER_TEMP on a runner, and the system's temporary folder
# elsewhere.
#
# The script reaches the window as a screen reader does. UI Automation
# finds each control by the AutomationId that its x:Name gives it, sets the
# focus to the text box, selects a row, and invokes Add and Remove. The
# characters and the Return key are posted to the window's input site
# (InputSiteWindowClass, the child that WinUI's window gives the keyboard
# to) as WM_CHAR and WM_KEYDOWN, which WinUI turns into the text box's
# input and its KeyDown event, as it does a keyboard's. Posted messages
# need no desktop that takes input, as the Win32 check's do not
# (check-basket-window.ps1). Basket's standard output is redirected to a
# file, since it is a GUI program.
#
# The Windows App Runtime is Microsoft's, which Windows registers for each
# person who installs it, from the Microsoft Store or with Microsoft's
# installer, and a runner image may or may not have it. Where the account
# has no Microsoft.WindowsAppRuntime.2 of version 2.7.0.0 or later, the
# script installs the framework package from Microsoft's NuGet package of
# the runtime, pinned by version and SHA-256, with Add-AppxPackage. The
# framework package is the one Basket asks Windows to add to its process
# (lib/basket/winrt.rb, FRAMEWORK); the runtime's main, singleton, and
# dynamic dependency lifetime manager packages serve features that Basket
# does not call.

param(
  [Parameter(Mandatory)] [string] $Archive,
  [Parameter(Mandatory)] [string] $Platform,
  [string] $Work = $(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# The Windows App Runtime, version 2.7.0, as Microsoft publishes it on
# nuget.org, and the SHA-256 of the .nupkg as downloaded on 2026-11-26.
$RuntimeUrl = 'https://api.nuget.org/v3-flatcontainer/microsoft.windowsappsdk.runtime/2.7.0/microsoft.windowsappsdk.runtime.2.7.0.nupkg'
$RuntimeSha256 = '326b47f40f051e767bfc83ce99c753c758bbba75a25f0a4febab8cd9ea8b5152'
$RuntimeVersion = [version] '2.7.0.0'
$FrameworkName = 'Microsoft.WindowsAppRuntime.2'

function Fail([string] $message) {
  Write-Host "::error::Delivery (Basket's WinUI screen): $message"
  exit 1
}

function Expect([string] $Label, $Actual, $Expected) {
  if ($Actual -cne $Expected) { Fail "$Label is '$Actual', not '$Expected'" }
  Write-Host "ok: $Label is $Expected"
}

if ($PSVersionTable.PSEdition -ne 'Desktop') { Fail 'run this script with powershell.exe (Windows PowerShell), which has UI Automation' }

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -Namespace Fledge -Name BasketWinUI -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr FindWindowExW(IntPtr parent, IntPtr after, string windowClass, string title);
[DllImport("user32.dll")]
public static extern bool PostMessageW(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam);
'@

# Running ExitProcess on a thread made in another process. kernel32.dll is
# the same file in both processes, so ExitProcess is at the same offset from
# its base in each, and the base in Basket comes from its list of modules.
Add-Type -Namespace Fledge -Name BasketExit -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr OpenProcess(uint access, bool inherit, uint id);
[DllImport("kernel32.dll")]
public static extern bool CloseHandle(IntPtr handle);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr GetModuleHandleW(string name);
[DllImport("kernel32.dll", CharSet = CharSet.Ansi)]
public static extern IntPtr GetProcAddress(IntPtr module, string name);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr CreateRemoteThread(IntPtr process, IntPtr attributes, UIntPtr stack, IntPtr start, IntPtr parameter, uint flags, out uint id);
[DllImport("psapi.dll", SetLastError = true)]
public static extern bool EnumProcessModulesEx(IntPtr process, IntPtr[] modules, uint size, out uint needed, uint filter);
[DllImport("psapi.dll", CharSet = CharSet.Unicode)]
public static extern uint GetModuleBaseNameW(IntPtr process, IntPtr module, System.Text.StringBuilder name, uint size);
'@

$WM_CLOSE = 0x10; $WM_KEYDOWN = 0x100; $WM_KEYUP = 0x101; $WM_CHAR = 0x102
$VK_RETURN = 0x0D
$Element = [Windows.Automation.AutomationElement]

# Waits up to 60 seconds for the block to say yes. WinUI's first window
# takes longer than Win32's.
function WaitFor([string] $What, [scriptblock] $Block) {
  $deadline = [DateTime]::UtcNow.AddSeconds(60)
  while (-not (& $Block)) {
    if ([DateTime]::UtcNow -gt $deadline) { Fail "Basket did not $What within 60 seconds`n$(Show-Log)" }
    Start-Sleep -Milliseconds 100
  }
}

function Show-Log {
  foreach ($file in $out, $err) { if (Test-Path -LiteralPath $file) { "$file`: $(Get-Content -LiteralPath $file -Raw)" } }
}

function Show-Log2 {
  foreach ($file in $out2, $err2) { if (Test-Path -LiteralPath $file) { "$file`: $(Get-Content -LiteralPath $file -Raw)" } }
}

function Post([IntPtr] $Window, [uint32] $Message, [uint64] $WParam, [int64] $LParam = 1) {
  if (-not [Fledge.BasketWinUI]::PostMessageW($Window, $Message, [UIntPtr]::new($WParam), [IntPtr]::new($LParam))) { Fail "PostMessage $Message failed" }
}

# Whether this account has the Windows App Runtime's framework package,
# at the version Basket asks for or a later one.
function Test-Runtime {
  @(Get-AppxPackage -Name $FrameworkName | Where-Object { $_.Version -ge $RuntimeVersion }).Count -gt 0
}

# Registers the framework package of Microsoft's runtime, from the NuGet
# package that this script pins, whose MSIX files are in tools\MSIX.
function Install-Runtime {
  $folder = switch ($Platform) {
    'x64-mingw-ucrt' { 'win10-x64' }
    'aarch64-mingw-ucrt' { 'win10-arm64' }
    default { Fail "the platform $Platform has no Windows App Runtime package" }
  }
  $dir = Join-Path $Work 'Windows App Runtime'
  New-Item -ItemType Directory -Force $dir | Out-Null
  $nupkg = Join-Path $dir 'runtime.nupkg'
  Invoke-WebRequest -UseBasicParsing -Uri $RuntimeUrl -OutFile $nupkg
  $actual = (Get-FileHash -LiteralPath $nupkg -Algorithm SHA256).Hash
  if ($actual -ne $RuntimeSha256) { Fail "the Windows App Runtime package's SHA-256 is $actual, not $RuntimeSha256" }
  $framework = Join-Path $dir "$FrameworkName.msix"
  $zip = [IO.Compression.ZipFile]::OpenRead($nupkg)
  try {
    $entry = $zip.GetEntry("tools/MSIX/$folder/Microsoft.WindowsAppRuntime.2.msix")
    if (-not $entry) { Fail "the Windows App Runtime package has no framework package for $folder" }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $framework, $true)
  } finally {
    $zip.Dispose()
  }
  Add-AppxPackage -Path $framework
  Write-Host "ok: registered Microsoft.WindowsAppRuntime.2 from the pinned NuGet package"
}

if (Test-Runtime) {
  Write-Host 'ok: the Windows App Runtime 2.7 or later is registered for this account'
} else {
  Install-Runtime
  if (-not (Test-Runtime)) { Fail 'Get-AppxPackage does not list Microsoft.WindowsAppRuntime.2 2.7.0.0 or later after Add-AppxPackage' }
}

$Archive = (Resolve-Path -LiteralPath $Archive).Path
$name = [IO.Path]::GetFileNameWithoutExtension($Archive)
$place = Join-Path (Join-Path $Work 'Fledge Basket WinUI') "b$([char]0xE4)sket"
New-Item -ItemType Directory -Force $place | Out-Null
Expand-Archive -LiteralPath $Archive -DestinationPath $place
$app = Join-Path (Join-Path $place $name) 'Basket.exe'
if (-not (Test-Path -LiteralPath $app -PathType Leaf)) { Fail "$app is missing after unpacking $Archive" }

# The runner has Rubies; the app's PATH keeps only the system's folders.
# Its list is basket.json in setdef\Basket\data under the Roaming AppData
# folder, which Basket takes from %APPDATA% when that is set, and which
# starts empty. BASKET_SCREEN is unset, so Basket chooses its screen as a
# person's Windows makes it choose.
$system = $env:SystemRoot
$env:PATH = "$system\System32;$system;$system\System32\Wbem;$system\System32\WindowsPowerShell\v1.0"
if (Get-Command ruby -ErrorAction SilentlyContinue) { Fail "Get-Command still finds a Ruby on $env:PATH" }
$home_folder = Join-Path $Work 'Basket WinUI home'
New-Item -ItemType Directory -Force $home_folder | Out-Null
Remove-Item Env:BASKET_SCREEN -ErrorAction SilentlyContinue
$env:HOME = $home_folder
$env:USERPROFILE = $home_folder
$env:APPDATA = Join-Path $Work 'Basket WinUI app data'
$list = Join-Path $env:APPDATA 'setdef\Basket\data\basket.json'
Remove-Item -LiteralPath $env:APPDATA -Recurse -ErrorAction SilentlyContinue
$out = Join-Path $Work 'basket-winui.out'
$err = Join-Path $Work 'basket-winui.err'
Remove-Item -LiteralPath $out, $err -ErrorAction SilentlyContinue

$process = Start-Process -FilePath $app -WorkingDirectory $system -PassThru `
  -RedirectStandardOutput $out -RedirectStandardError $err
# PowerShell reads ExitCode as empty, for a process that was not waited on
# with -Wait, unless something has asked for the process's handle first.
$null = $process.Handle

# The control of the window with the AutomationId +id+, or $null.
function Control([string] $Id) {
  try {
    $window.FindFirst('Descendants', (New-Object Windows.Automation.PropertyCondition($Element::AutomationIdProperty, $Id)))
  } catch {
    $null
  }
}

# The text of each row of the list, in order.
function Rows {
  try {
    @($script:rows.FindAll('Children', [Windows.Automation.Condition]::TrueCondition) | ForEach-Object { $_.Current.Name })
  } catch {
    @()
  }
}

function FieldText {
  $script:field.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value
}

# Windows can put windows in a GUI process, so Basket's window is the
# top-level window of the process that is called Basket.
$name_condition = New-Object Windows.Automation.PropertyCondition($Element::NameProperty, 'Basket')
$process_condition = New-Object Windows.Automation.PropertyCondition($Element::ProcessIdProperty, $process.Id)
$both = New-Object Windows.Automation.AndCondition($name_condition, $process_condition)
WaitFor 'show a window' {
  $script:window = $Element::RootElement.FindFirst('Children', $both)
  $null -ne $script:window
}
$window = $script:window
# WinUI's window class, which Basket's Win32 window does not have: Basket
# drew its WinUI screen, not the one a Windows without the runtime gets.
Expect "the window's class" $window.Current.ClassName 'WinUIDesktopWin32WindowClass'
WaitFor 'show a text box, an Add button, a list, and a Remove button' {
  $script:field = Control 'Field'
  $script:add = Control 'AddButton'
  $script:rows = Control 'Rows'
  $script:remove = Control 'RemoveButton'
  $script:field -and $script:add -and $script:rows -and $script:remove
}
$field = $script:field; $add = $script:add; $rows = $script:rows; $remove = $script:remove
Expect 'the text box is a' $field.Current.ControlType.ProgrammaticName 'ControlType.Edit'
Expect 'the list is a' $rows.Current.ControlType.ProgrammaticName 'ControlType.List'
Expect 'the buttons are' "$($add.Current.Name), $($remove.Current.Name)" 'Add, Remove'
Write-Host 'ok: the window has a text box, an Add button, a list, and a Remove button'

# The keyboard goes to the window's input site, which holds the child of
# the top-level window that WinUI makes for input.
$top = [IntPtr] $window.Current.NativeWindowHandle
$bridge = [Fledge.BasketWinUI]::FindWindowExW($top, [IntPtr]::Zero, 'Microsoft.UI.Content.DesktopChildSiteBridge', [NullString]::Value)
$input_site = [Fledge.BasketWinUI]::FindWindowExW($bridge, [IntPtr]::Zero, 'InputSiteWindowClass', [NullString]::Value)
if ($input_site -eq [IntPtr]::Zero) { Fail "the window has no InputSiteWindowClass child`n$(Show-Log)" }

function Enter-Text([string] $Text) {
  $field.SetFocus()
  WaitFor 'give the text box the keyboard' { $field.Current.HasKeyboardFocus }
  foreach ($character in $Text.ToCharArray()) { Post $input_site $WM_CHAR ([uint64] $character) }
  WaitFor "show $Text in the text box" { (FieldText) -ceq $Text }
}

Expect 'the rows at the start' ((Rows) -join ',') ''

# Type, then Add: the button takes what the text box holds into a row and
# empties the box.
Enter-Text 'Eggs'
$add.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
WaitFor 'add a row when Add was pressed' { ((Rows) -join ',') -ceq 'Eggs' }
WaitFor 'empty the text box' { (FieldText) -ceq '' }
Write-Host 'ok: Add took Eggs into a row and emptied the text box'

# Type, then Return: the text box adds as Add does.
Enter-Text 'Milk'
Post $input_site $WM_KEYDOWN $VK_RETURN 0x001C0001
Post $input_site $WM_KEYUP $VK_RETURN 0xC01C0001
WaitFor 'add a row when Return was pressed' { ((Rows) -join ',') -ceq 'Eggs,Milk' }
WaitFor 'empty the text box' { (FieldText) -ceq '' }
Write-Host 'ok: Return took Milk into a row and emptied the text box'

# Select the first row, as a click on it does, and press Remove.
$first = $rows.FindFirst('Children', [Windows.Automation.Condition]::TrueCondition)
$first.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
Expect 'the selected row is' $first.Current.Name 'Eggs'
$remove.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
WaitFor 'remove the row when Remove was pressed' { ((Rows) -join ',') -ceq 'Milk' }
Write-Host 'ok: Remove took Eggs away'

Post $top $WM_CLOSE 0 0
if (-not $process.WaitForExit(30000)) { Fail "Basket did not exit when its window was closed`n$(Show-Log)" }
Expect 'the exit status' $process.ExitCode 0
$lines = @(Get-Content -LiteralPath $out)
# Basket logs its list's path with the slashes Ruby's Pathname joins it
# with, which Windows reads as the same path.
Expect 'where Basket said it keeps its list' ($lines[0] -replace '/', '\') "Basket keeps its list in $list"
Expect 'what Basket logged after that' ($lines[1..($lines.Count - 1)] -join '|') 'Basket shows 0 items|Basket added Eggs|Basket added Milk|Basket removed Eggs'
Expect 'what Basket saved in its list' ((Get-Content -LiteralPath $list -Raw) -replace '\s+$', '') '["Milk"]'
Expect 'what Basket wrote to standard error' ((Get-Content -LiteralPath $err -Raw) -replace '\s+$', '') ''

# Ending Basket from a thread Ruby did not make. ExitProcess on such a
# thread has Windows release Basket's COM objects there, and their AddRef
# and Release must call no Ruby.
$out2 = Join-Path $Work 'basket-winui-exit.out'
$err2 = Join-Path $Work 'basket-winui-exit.err'
Remove-Item -LiteralPath $out2, $err2 -ErrorAction SilentlyContinue
$second = Start-Process -FilePath $app -WorkingDirectory $system -PassThru `
  -RedirectStandardOutput $out2 -RedirectStandardError $err2
$null = $second.Handle
$process_condition = New-Object Windows.Automation.PropertyCondition($Element::ProcessIdProperty, [int] $second.Id)
$both = New-Object Windows.Automation.AndCondition($name_condition, $process_condition)
WaitFor 'show a window to end from another thread' {
  $script:window = $Element::RootElement.FindFirst('Children', $both)
  $null -ne $script:window
}
$window = $script:window
WaitFor 'show its list before it is ended' { $null -ne (Control 'Rows') }

$PROCESS_ALL_ACCESS = 0x1FFFFF; $LIST_MODULES_ALL = 3; $EXIT_STATUS = 3
$handle = [Fledge.BasketExit]::OpenProcess($PROCESS_ALL_ACCESS, $false, [uint32] $second.Id)
if ($handle -eq [IntPtr]::Zero) { Fail "OpenProcess failed with error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
$modules = New-Object IntPtr[] 1024
$needed = [uint32] 0
if (-not [Fledge.BasketExit]::EnumProcessModulesEx($handle, $modules, [uint32] ($modules.Length * [IntPtr]::Size), [ref] $needed, $LIST_MODULES_ALL)) {
  Fail "EnumProcessModulesEx failed with error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}
$remote_kernel32 = [IntPtr]::Zero
foreach ($module in $modules[0..([int] ($needed / [IntPtr]::Size) - 1)]) {
  $name_buffer = New-Object Text.StringBuilder 260
  [void] [Fledge.BasketExit]::GetModuleBaseNameW($handle, $module, $name_buffer, 260)
  if ($name_buffer.ToString() -ieq 'kernel32.dll') { $remote_kernel32 = $module }
}
if ($remote_kernel32 -eq [IntPtr]::Zero) { Fail "Basket's process lists no kernel32.dll" }
$local_kernel32 = [Fledge.BasketExit]::GetModuleHandleW('kernel32.dll')
$offset = [int64] [Fledge.BasketExit]::GetProcAddress($local_kernel32, 'ExitProcess') - [int64] $local_kernel32
$thread_id = [uint32] 0
$thread = [Fledge.BasketExit]::CreateRemoteThread($handle, [IntPtr]::Zero, [UIntPtr]::Zero, [IntPtr] ([int64] $remote_kernel32 + $offset), [IntPtr] $EXIT_STATUS, 0, [ref] $thread_id)
if ($thread -eq [IntPtr]::Zero) { Fail "CreateRemoteThread failed with error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
[void] [Fledge.BasketExit]::CloseHandle($thread)
[void] [Fledge.BasketExit]::CloseHandle($handle)
if (-not $second.WaitForExit(30000)) { $second.Kill(); Fail "Basket did not exit when ExitProcess ran in it`n$(Show-Log2)" }
Expect 'the exit status when ExitProcess ran on another thread' $second.ExitCode $EXIT_STATUS
$report = Get-Content -LiteralPath $err2 -Raw
if ($report -match '\[BUG\]') { Fail "Basket's standard error holds a CRuby [BUG] after ExitProcess ran on another thread`n$report" }
Write-Host 'ok: Basket printed no [BUG] when ExitProcess ran on another thread'

Write-Host "Delivered: Basket's WinUI screen, on Windows"
