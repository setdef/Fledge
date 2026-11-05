# Runs the Lota trial's built app on a Windows runner with no Ruby on
# its PATH, in stages, recording each and going on: the game with no
# window, the windowed game on Windows' own OpenGL, the windowed game
# with Mesa's software OpenGL and Vulkan beside the program, the same
# started through the shell, and the setup program installed, run, and
# uninstalled. Every stage writes to RESULTS; screenshots are PNGs there.
#
#   pwsh -NoProfile -File run-on-windows.ps1 -Dist DIST -Platform PLATFORM -Results RESULTS [-Mesa MESA]
#
# MESA is a folder of Mesa's opengl32.dll, vulkan_lvp.dll, lavapipe's
# driver manifest, and the DLLs they need, or nothing to skip the stages
# that need it.

param(
  [Parameter(Mandatory)] [string] $Dist,
  [Parameter(Mandatory)] [string] $Platform,
  [Parameter(Mandatory)] [string] $Results,
  [string] $Mesa = ''
)

. (Join-Path $PSScriptRoot 'helpers.ps1')

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


# The software renderers Mesa gives a computer with no GPU, as the
# settings that choose each for the program in $Folder: llvmpipe, its
# OpenGL, and lavapipe, its Vulkan, named to the Vulkan loader by the
# driver manifest beside the program (VK_DRIVER_FILES) and asked of the
# game by its conf.rb (LOTA_TRIAL_RENDERERS). Lota's ARM64 build has no
# OpenGL (its SDL is built with SDL_OPENGL off), so there the game is
# expected to draw with lavapipe, and elsewhere with llvmpipe.
function Soft-Settings([string] $Kind, [string] $Folder) {
  if ($Kind -eq 'llvmpipe') { return @{ GALLIUM_DRIVER = 'llvmpipe' } }
  $manifest = Join-Path $Folder 'lvp_icd.json'
  @{ VK_DRIVER_FILES = $manifest; VK_ICD_FILENAMES = $manifest; LOTA_TRIAL_RENDERERS = 'vulkan'; LOVE_GRAPHICS_VULKAN_ALLOW_SOFTWARE = '1' }
}
$expected = if ($Platform -eq 'aarch64-mingw-ucrt') { 'lavapipe' } else { 'llvmpipe' }
$expectedRenderer = if ($expected -eq 'lavapipe') { 'renderer: Vulkan' } else { 'renderer: OpenGL' }

function With-Settings([hashtable] $Base, [hashtable] $Extra) {
  $copy = $Base.Clone()
  foreach ($key in $Extra.Keys) { $copy[$key] = $Extra[$key] }
  $copy
}

# Starts $Target through the shell, as Explorer or the Start menu starts
# it, with $Extra in the environment it inherits, and reads what the
# game said from its log file.
function Run-Shell([string] $Label, [string] $Target, [hashtable] $Extra) {
  Section "run: $Label"
  $log = Join-Path $Results "$Label.log"
  $env:LOTA_TRIAL_LOG = $log
  $env:ALSOFT_DRIVERS = 'null'
  foreach ($key in $Extra.Keys) { Set-Item -Path "Env:\$key" -Value $Extra[$key] }
  Start-Process -FilePath $Target -WorkingDirectory $system
  Start-Sleep -Seconds 3
  Save-Screen (Join-Path $Results "$Label.png")
  $deadline = (Get-Date).AddSeconds(90)
  while ((Get-Date) -lt $deadline -and -not ((Test-Path -LiteralPath $log) -and (Get-Content -LiteralPath $log -Raw) -match 'exiting with')) {
    Start-Sleep -Milliseconds 500
  }
  Get-Process LotaTrial -ErrorAction SilentlyContinue | ForEach-Object {
    Save-Windows $Label $_
    $_.Kill($true)
    Write-Host "killed LotaTrial ($($_.Id)), still running after 90 s"
  }
  Remove-Item Env:\LOTA_TRIAL_LOG, Env:\ALSOFT_DRIVERS
  foreach ($key in $Extra.Keys) { Remove-Item -Path "Env:\$key" }
  $said = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
  Write-Host $said
  Add-Content -LiteralPath $statuses -Value "$Label $(if ($said -match 'exiting with (\d+)') { $Matches[1] } else { 'no exit line' })"
  Collect-Frame $Label
  $said
}

if ($Mesa) {
  Section "Mesa's software renderers beside the program"
  $mesaFiles = Get-ChildItem -LiteralPath $Mesa -File
  $mesaFiles | ForEach-Object { Write-Host $_.Name }
  $mesaFiles | Copy-Item -Destination $root
  Register-Driver (Join-Path $root 'lvp_icd.json')
  Section 'whether the Mesa DLLs load here'
  Test-Load @((Join-Path $env:SystemRoot 'System32\opengl32.dll'), (Join-Path $env:SystemRoot 'System32\vulkan-1.dll'),
    (Join-Path $root 'opengl32.dll'), (Join-Path $root 'libgallium_wgl.dll'), (Join-Path $root 'vulkan_lvp.dll'))

  foreach ($kind in 'llvmpipe', 'lavapipe') {
    $run = Run-App "window-$kind" $app (With-Settings $nullAudio (Soft-Settings $kind $root)) @() 2.5 90
    Collect-Frame "window-$kind"
    if ($kind -eq $expected) {
      Expect "the windowed game draws with $kind, plays its tone, and quits by itself with 0" ($run.Code -eq 0 -and
        $run.Out -match $expectedRenderer -and $run.Out -match 'audio: 1 source playing' -and $run.Out -match 'frames in')
    }
  }

  # Mesa's OpenGL on Direct3D 12, on WARP, Windows' own software
  # Direct3D, for comparison; not expected of anything.
  $null = Run-App 'window-mesa-d3d12' $app (With-Settings $nullAudio @{ GALLIUM_DRIVER = 'd3d12' }) @() 2.5 60
  Collect-Frame 'window-mesa-d3d12'

  $said = Run-Shell "window-$expected-shell" $app (Soft-Settings $expected $root)
  Expect "started through the shell, it draws with $expected and quits with 0" ($said -match 'exiting with 0' -and $said -match 'frames in')
  Unregister-Driver (Join-Path $root 'lvp_icd.json')
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
  $installedQuiet = Run-App 'installed-quiet' $installed $nullAudio @('quiet')
  Expect 'installed, the game with no window plays a sound and exits 3' ($installedQuiet.Code -eq 3 -and
    $installedQuiet.Out -match 'Windows: 1 source playing')
  if ($Mesa) {
    $mesaFiles = Get-ChildItem -LiteralPath $Mesa -File
    $mesaFiles | Copy-Item -Destination $folder
    Register-Driver (Join-Path $folder 'lvp_icd.json')
    $said = Run-Shell "installed-shortcut-$expected" $shortcut (Soft-Settings $expected $folder)
    Expect "started from its Start menu shortcut, it draws with $expected and quits with 0" ($said -match 'exiting with 0' -and $said -match 'frames in')
    Unregister-Driver (Join-Path $folder 'lvp_icd.json')
    $mesaFiles | ForEach-Object { Remove-Item -LiteralPath (Join-Path $folder $_.Name) }
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
