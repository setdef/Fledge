# Runs the Lota trial's built app on a Windows runner with no Ruby on
# its PATH, in stages, recording each and going on: the game with no
# window, the windowed game on Windows' own OpenGL, the windowed game
# with Mesa's software OpenGL beside the program, the same started
# through the shell, and the setup program installed, run, and
# uninstalled. Every stage writes to RESULTS; screenshots are PNGs there.
#
#   pwsh -NoProfile -File run-on-windows.ps1 -Dist DIST -Platform PLATFORM -Results RESULTS [-Mesa MESA]
#
# MESA is a folder of Mesa's opengl32.dll and the DLLs it needs, or
# nothing to skip the stages that need it.

param(
  [Parameter(Mandatory)] [string] $Dist,
  [Parameter(Mandatory)] [string] $Platform,
  [Parameter(Mandatory)] [string] $Results,
  [string] $Mesa = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
New-Item -ItemType Directory -Force $Results | Out-Null
$Results = (Resolve-Path -LiteralPath $Results).Path
$statuses = Join-Path $Results 'statuses.txt'
Set-Content -LiteralPath $statuses -Value ''
$failed = @()

function Section([string] $title) { Write-Host "`n========== $title ==========" }

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# A PNG of the whole screen, as a person would see it.
function Save-Screen([string] $Path) {
  try {
    $bounds = [Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = [Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.Size)
    $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose(); $bitmap.Dispose()
    Write-Host "screenshot: $Path ($($bounds.Width)x$($bounds.Height))"
  } catch {
    Write-Host "screenshot failed: $($_.Exception.Message)"
  }
}

# The text of every window a process has open, its children's too, as a
# message box holds its message in a Static child: what a person would
# read on the screen, even when another window covers it.
Add-Type -Namespace Trial -Name Windows -MemberDefinition @'
public delegate bool EnumProc(System.IntPtr window, System.IntPtr data);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc proc, System.IntPtr data);
[DllImport("user32.dll")] public static extern bool EnumChildWindows(System.IntPtr parent, EnumProc proc, System.IntPtr data);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr window, out uint process);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(System.IntPtr window, System.Text.StringBuilder text, int size);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(System.IntPtr window, System.Text.StringBuilder text, int size);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr window);
public static System.Collections.Generic.List<string> Texts(uint pid) {
  var texts = new System.Collections.Generic.List<string>();
  EnumWindows((window, data) => {
    uint owner; GetWindowThreadProcessId(window, out owner);
    if (owner != pid) return true;
    texts.Add("window " + Describe(window) + (IsWindowVisible(window) ? "" : " (hidden)"));
    EnumChildWindows(window, (child, d) => { texts.Add("  child " + Describe(child)); return true; }, System.IntPtr.Zero);
    return true;
  }, System.IntPtr.Zero);
  return texts;
}
static string Describe(System.IntPtr window) {
  var name = new System.Text.StringBuilder(256); GetClassName(window, name, 256);
  var text = new System.Text.StringBuilder(4096); GetWindowText(window, text, 4096);
  return "[" + name + "] " + text.ToString().Replace("\r", "").Replace("\n", " | ");
}
'@

# What a running process shows and which OpenGL it loaded, saved as
# LABEL-windows.txt.
function Save-Windows([string] $Label, [Diagnostics.Process] $Process) {
  try {
    $lines = @([Trial.Windows]::Texts([uint32]$Process.Id))
    $lines += ($Process.Modules | Where-Object { $_.ModuleName -match 'opengl32|gallium|llvm|vulkan|openal|d3d|dxgi' } |
      ForEach-Object { "module $($_.FileName)" })
  } catch {
    $lines = @("could not read the process's windows: $($_.Exception.Message)")
  }
  Set-Content -LiteralPath (Join-Path $Results "$Label-windows.txt") -Value $lines
  Write-Host '--- its windows and graphics modules'; $lines | ForEach-Object { Write-Host $_ }
}

# Runs $Program with exactly $Environment, captures both streams, takes a
# screenshot $Shot seconds in when $Shot is above 0, and kills it after
# $Timeout seconds, first saving the text of its windows. Records LABEL
# STATUS in statuses.txt.
function Run-App([string] $Label, [string] $Program, [hashtable] $Environment, [string[]] $Arguments = @(),
  [double] $Shot = 0, [int] $Timeout = 90) {
  Section "run: $Label"
  $info = [Diagnostics.ProcessStartInfo]::new($Program)
  foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
  $info.UseShellExecute = $false
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
  $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
  $info.WorkingDirectory = $env:SystemRoot
  $info.Environment.Clear()
  foreach ($name in $Environment.Keys) { $info.Environment[$name] = $Environment[$name] }
  $started = Get-Date
  $process = [Diagnostics.Process]::Start($info)
  $out = $process.StandardOutput.ReadToEndAsync()
  $err = $process.StandardError.ReadToEndAsync()
  if ($Shot -gt 0) {
    Start-Sleep -Milliseconds ([int]($Shot * 1000))
    Save-Screen (Join-Path $Results "$Label.png")
    if (-not $process.HasExited) { Save-Windows $Label $process }
  }
  $code = if ($process.WaitForExit($Timeout * 1000)) { $process.ExitCode } else {
    Save-Windows "$Label-at-timeout" $process
    $process.Kill($true)
    'timeout'
  }
  $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
  $stdout = $out.GetAwaiter().GetResult()
  $stderr = $err.GetAwaiter().GetResult()
  Set-Content -LiteralPath (Join-Path $Results "$Label.out") -Value $stdout
  Set-Content -LiteralPath (Join-Path $Results "$Label.err") -Value $stderr
  Write-Host "exit status: $code after $seconds s"
  Write-Host '--- stdout'; Write-Host $stdout
  Write-Host '--- stderr (last 40 lines)'; Write-Host (($stderr -split "`n" | Select-Object -Last 40) -join "`n")
  Add-Content -LiteralPath $statuses -Value "$Label $code"
  [pscustomobject]@{ Out = $stdout; Err = $stderr; Code = $code }
}

function Expect([string] $Label, [bool] $Condition) {
  if ($Condition) { Write-Host "ok: $Label" } else { Write-Host "::warning::not ok: $Label"; $script:failed += $Label }
}

# The save folder of a fused Lota game named LotaTrial, where its frame.png goes.
$save = Join-Path $env:APPDATA 'LotaTrial'

function Collect-Frame([string] $Label) {
  $frame = Join-Path $save 'frame.png'
  if (Test-Path -LiteralPath $frame) {
    Move-Item -LiteralPath $frame -Destination (Join-Path $Results "$Label-frame.png") -Force
    Write-Host "the game's own frame: $Label-frame.png"
  } else {
    Write-Host "the game wrote no frame.png in $save"
  }
}

Section 'computer'
$os = Get-CimInstance Win32_OperatingSystem
Write-Host "$($os.Caption) $($os.Version) $($os.OSArchitecture)"
Write-Host "process architecture: $([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture)"
Write-Host "interactive: $([Environment]::UserInteractive), session $([Diagnostics.Process]::GetCurrentProcess().SessionId)"
Get-CimInstance Win32_VideoController | ForEach-Object { Write-Host "display adapter: $($_.Name), driver $($_.DriverVersion), $($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)" }
Get-CimInstance Win32_SoundDevice | ForEach-Object { Write-Host "sound device: $($_.Name) ($($_.Status))" }
Write-Host "audio service: $((Get-Service Audiosrv -ErrorAction SilentlyContinue).Status)"
foreach ($dll in 'opengl32.dll', 'vulkan-1.dll', 'd3d12.dll', 'dxgi.dll', 'avrt.dll', 'dwmapi.dll', 'imm32.dll', 'setupapi.dll') {
  $path = Join-Path $env:SystemRoot "System32\$dll"
  $version = if (Test-Path $path) { (Get-Item $path).VersionInfo.FileVersion } else { 'absent' }
  Write-Host "System32\${dll}: $version"
}

# Unpack where it was never built, under a folder with a space and
# characters outside ASCII, with Windows' own Expand-Archive.
$archive = Join-Path $Dist "LotaTrial-$Platform.zip"
$drive = if (Test-Path 'D:\') { 'D:\' } else { $env:RUNNER_TEMP }
$place = Join-Path (Join-Path $drive 'Lota trial') "j$([char]0xF6)go"
New-Item -ItemType Directory -Force $place | Out-Null
Expand-Archive -LiteralPath $archive -DestinationPath $place
$root = Join-Path $place "LotaTrial-$Platform"
$app = Join-Path $root 'LotaTrial.exe'
Section "the app's folder"
Get-ChildItem -LiteralPath $root | ForEach-Object { Write-Host $_.Name }
Get-ChildItem -LiteralPath $root -Recurse -Include '*.dll', '*.so' | Where-Object { $_.FullName -match '\\lota-0\.' } |
  ForEach-Object { Write-Host "lota's compiled file: $($_.FullName.Substring($root.Length))" }
Get-ChildItem -LiteralPath $root -Recurse -Filter '*.tar.bz2' | ForEach-Object { Write-Host "source archive in the app: $($_.FullName.Substring($root.Length))" }

# The runner has Rubies; the app sees only Windows' own folders.
$system = $env:SystemRoot
$env:PATH = "$system\System32;$system;$system\System32\Wbem;$system\System32\WindowsPowerShell\v1.0"
if (Get-Command ruby -ErrorAction SilentlyContinue) { throw "Get-Command still finds a Ruby on $env:PATH" }
Write-Host "no Ruby on PATH: $env:PATH"

$work = Join-Path $env:RUNNER_TEMP 'lota-trial-temp'
New-Item -ItemType Directory -Force $work | Out-Null
$clean = @{
  SystemRoot = $system
  SystemDrive = $env:SystemDrive
  windir = $system
  PATH = $env:PATH
  USERPROFILE = $env:USERPROFILE
  APPDATA = $env:APPDATA
  LOCALAPPDATA = $env:LOCALAPPDATA
  TEMP = $work
  TMP = $work
}

# A runner has no audio endpoint, so OpenAL Soft opens no device unless
# it is told to use its null backend, which plays to nowhere, as Lota's
# own CI runs its Windows games (ALSOFT_DRIVERS, OpenAL Soft's own
# setting).
$quiet = Run-App 'quiet' $app $clean @('quiet')
Write-Host "with the runner's audio: $(if ($quiet.Out -match 'Could not open device') { 'no device' } else { 'a device' })"
$nullAudio = $clean.Clone()
$nullAudio['ALSOFT_DRIVERS'] = 'null'
$quietNull = Run-App 'quiet-null-audio' $app $nullAudio @('quiet')
Expect "the game with no window plays a sound through OpenAL Soft's null backend and exits 3" ($quietNull.Code -eq 3 -and
  $quietNull.Out -match 'Windows: 1 source playing')

$plain = Run-App 'window-windows-opengl' $app $nullAudio @() 2.5 60
Collect-Frame 'window-windows-opengl'

if ($Mesa) {
  Section "Mesa's software OpenGL beside the program"
  $mesaFiles = Get-ChildItem -LiteralPath $Mesa -Filter '*.dll'
  $mesaFiles | ForEach-Object { Write-Host $_.Name }
  $mesaFiles | Copy-Item -Destination $root
  $llvmpipe = $nullAudio.Clone()
  $llvmpipe['GALLIUM_DRIVER'] = 'llvmpipe'
  $soft = Run-App 'window-mesa-llvmpipe' $app $llvmpipe @() 2.5 90
  Collect-Frame 'window-mesa-llvmpipe'
  Expect 'the windowed game draws with llvmpipe, plays its tone, and quits by itself with 0' ($soft.Code -eq 0 -and
    $soft.Out -match 'renderer: OpenGL' -and $soft.Out -match 'audio: 1 source playing' -and $soft.Out -match 'frames in')

  # Mesa's OpenGL on Direct3D 12, on WARP, Windows' own software
  # Direct3D, for comparison; not expected of anything.
  $d3d12 = $nullAudio.Clone()
  $d3d12['GALLIUM_DRIVER'] = 'd3d12'
  $null = Run-App 'window-mesa-d3d12' $app $d3d12 @() 2.5 60
  Collect-Frame 'window-mesa-d3d12'

  # As Explorer starts it: through the shell, no streams, the log file.
  Section 'run: window-mesa-shell'
  $log = Join-Path $Results 'window-mesa-shell.log'
  $env:LOTA_TRIAL_LOG = $log
  $env:GALLIUM_DRIVER = 'llvmpipe'
  $env:ALSOFT_DRIVERS = 'null'
  $process = Start-Process -FilePath $app -WorkingDirectory $system -PassThru
  Start-Sleep -Seconds 2.5
  Save-Screen (Join-Path $Results 'window-mesa-shell.png')
  if (-not $process.HasExited) { Save-Windows 'window-mesa-shell' $process }
  if (-not $process.WaitForExit(90000)) { $process.Kill($true) }
  Remove-Item Env:\LOTA_TRIAL_LOG, Env:\GALLIUM_DRIVER, Env:\ALSOFT_DRIVERS
  $shellLog = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
  Write-Host "exit status: $($process.ExitCode)"; Write-Host $shellLog
  Add-Content -LiteralPath $statuses -Value "window-mesa-shell $($process.ExitCode)"
  Collect-Frame 'window-mesa-shell'
  Expect 'started through the shell, it draws and quits with 0' ($process.ExitCode -eq 0 -and $shellLog -match 'frames in')
  $mesaFiles | ForEach-Object { Remove-Item -LiteralPath (Join-Path $root $_.Name) }
}

$installer = Join-Path $Dist "LotaTrial-$Platform-setup.exe"
if (Test-Path -LiteralPath $installer) {
  Section 'install with the setup program'
  $setup = Start-Process -FilePath $installer -ArgumentList '/S' -Wait -PassThru
  Write-Host "silent install exit status: $($setup.ExitCode)"
  $folder = Join-Path $env:LOCALAPPDATA 'Programs\LotaTrial'
  $installed = Join-Path $folder 'LotaTrial.exe'
  Expect 'the setup program installs LotaTrial.exe' ($setup.ExitCode -eq 0 -and (Test-Path -LiteralPath $installed))
  $shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'LotaTrial.lnk'
  Write-Host "Start menu shortcut: $(Test-Path -LiteralPath $shortcut)"
  $installedQuiet = Run-App 'installed-quiet' $installed $clean @('quiet')
  Expect 'installed, the game with no window exits 3' ($installedQuiet.Code -eq 3)
  if ($Mesa) {
    Get-ChildItem -LiteralPath $Mesa -Filter '*.dll' | Copy-Item -Destination $folder
    Section 'run: installed-shortcut-mesa'
    $log = Join-Path $Results 'installed-shortcut-mesa.log'
    $env:LOTA_TRIAL_LOG = $log
    $env:GALLIUM_DRIVER = 'llvmpipe'
    $env:ALSOFT_DRIVERS = 'null'
    Start-Process -FilePath $shortcut
    Start-Sleep -Seconds 3
    Save-Screen (Join-Path $Results 'installed-shortcut-mesa.png')
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline -and -not ((Test-Path -LiteralPath $log) -and (Get-Content -LiteralPath $log -Raw) -match 'exiting with')) {
      Start-Sleep -Milliseconds 500
    }
    Get-Process LotaTrial -ErrorAction SilentlyContinue | ForEach-Object {
      Save-Windows 'installed-shortcut-mesa' $_
      $_.Kill($true)
      Write-Host "killed LotaTrial ($($_.Id)), still running after 90 s"
    }
    Remove-Item Env:\LOTA_TRIAL_LOG, Env:\GALLIUM_DRIVER, Env:\ALSOFT_DRIVERS
    $shortcutLog = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
    Write-Host $shortcutLog
    Add-Content -LiteralPath $statuses -Value "installed-shortcut-mesa $(if ($shortcutLog -match 'exiting with (\d+)') { $Matches[1] } else { 'no exit line' })"
    Collect-Frame 'installed-shortcut-mesa'
    Expect 'started from its Start menu shortcut, it draws and quits' ($shortcutLog -match 'exiting with 0')
    Get-ChildItem -LiteralPath $Mesa -Filter '*.dll' | ForEach-Object { Remove-Item -LiteralPath (Join-Path $folder $_.Name) }
  }
  $uninstall = Start-Process -FilePath (Join-Path $folder 'uninstall.exe') -ArgumentList '/S' -Wait -PassThru
  Write-Host "silent uninstall exit status: $($uninstall.ExitCode)"
  Start-Sleep -Seconds 5
  Write-Host "installed folder still there: $(Test-Path -LiteralPath $folder)"
} else {
  Write-Host "no setup program at $installer"
}

Section 'statuses'
Get-Content -LiteralPath $statuses | Write-Host
if ($failed.Count -gt 0) {
  Write-Host "::error::not ok: $($failed -join '; ')"
  exit 1
}
