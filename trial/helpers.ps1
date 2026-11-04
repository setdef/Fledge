# What the Lota trial's scripts share: a screenshot, the text of a
# process's windows, a run of a program with exactly the environment it
# is given, a check that is recorded and goes on, and whether a DLL
# loads. Dot-source it after setting $Results.

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

# Whether each DLL loads into this process by its full path, with the
# DLLs it imports looked for beside it first (LOAD_WITH_ALTERED_SEARCH_PATH),
# and Windows' error when it does not: 126 is a DLL it imports that is
# nowhere, 193 one for another processor.
Add-Type -Namespace Trial -Name Loader -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern System.IntPtr LoadLibraryExW(string path, System.IntPtr file, uint flags);
[DllImport("kernel32.dll")] public static extern bool FreeLibrary(System.IntPtr module);
'@
function Test-Load([string[]] $Paths) {
  foreach ($path in $Paths) {
    $module = [Trial.Loader]::LoadLibraryExW($path, [IntPtr]::Zero, 0x8)
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($module -eq [IntPtr]::Zero) {
      Write-Host "does not load: $path (Windows error $err)"
    } else {
      Write-Host "loads: $path"
      $null = [Trial.Loader]::FreeLibrary($module)
    }
  }
}
