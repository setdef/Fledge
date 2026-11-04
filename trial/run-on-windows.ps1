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

# Runs $Program with exactly $Environment, captures both streams, takes a
# screenshot $Shot seconds in when $Shot is above 0, and kills it after
# $Timeout seconds. Records LABEL STATUS in statuses.txt.
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
  }
  $code = if ($process.WaitForExit($Timeout * 1000)) { $process.ExitCode } else { $process.Kill($true); 'timeout' }
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
Get-ChildItem -LiteralPath $root -Recurse -Filter '*.dll' | Where-Object { $_.FullName -match 'lota' } | ForEach-Object { Write-Host "lota's DLL: $($_.FullName.Substring($root.Length))" }
Get-ChildItem -LiteralPath $root -Recurse -Filter '*.so' | Where-Object { $_.FullName -match 'lota' } | ForEach-Object { Write-Host "lota's extension: $($_.FullName.Substring($root.Length))" }
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

$quiet = Run-App 'quiet' $app $clean @('quiet')
Expect 'the game with no window plays a sound and exits 3' ($quiet.Code -eq 3 -and $quiet.Out -match 'Windows: 1 source playing')

$plain = Run-App 'window-windows-opengl' $app $clean @() 2.5 60
Collect-Frame 'window-windows-opengl'

if ($Mesa) {
  Section "Mesa's software OpenGL beside the program"
  $mesaFiles = Get-ChildItem -LiteralPath $Mesa -Filter '*.dll'
  $mesaFiles | ForEach-Object { Write-Host $_.Name }
  $mesaFiles | Copy-Item -Destination $root
  $llvmpipe = $clean.Clone()
  $llvmpipe['GALLIUM_DRIVER'] = 'llvmpipe'
  $soft = Run-App 'window-mesa-llvmpipe' $app $llvmpipe @() 2.5 90
  Collect-Frame 'window-mesa-llvmpipe'
  Expect 'the windowed game draws with llvmpipe, plays its tone, and quits by itself with 0' ($soft.Code -eq 0 -and
    $soft.Out -match 'renderer: OpenGL' -and $soft.Out -match 'audio: 1 source playing' -and $soft.Out -match 'frames in')

  # As Explorer starts it: through the shell, no streams, the log file.
  Section 'run: window-mesa-shell'
  $log = Join-Path $Results 'window-mesa-shell.log'
  $env:LOTA_TRIAL_LOG = $log
  $env:GALLIUM_DRIVER = 'llvmpipe'
  $process = Start-Process -FilePath $app -WorkingDirectory $system -PassThru
  Start-Sleep -Seconds 2.5
  Save-Screen (Join-Path $Results 'window-mesa-shell.png')
  if (-not $process.WaitForExit(90000)) { $process.Kill($true) }
  Remove-Item Env:\LOTA_TRIAL_LOG, Env:\GALLIUM_DRIVER
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
    Start-Process -FilePath $shortcut
    Start-Sleep -Seconds 3
    Save-Screen (Join-Path $Results 'installed-shortcut-mesa.png')
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline -and -not ((Test-Path -LiteralPath $log) -and (Get-Content -LiteralPath $log -Raw) -match 'exiting with')) {
      Start-Sleep -Milliseconds 500
    }
    Remove-Item Env:\LOTA_TRIAL_LOG, Env:\GALLIUM_DRIVER
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
