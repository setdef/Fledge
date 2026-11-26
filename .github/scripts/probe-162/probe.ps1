# Probe 162 (a spike, never for trunk): gathers facts about why WinUI's
# XamlControlsResources fails to activate in Basket on Windows on ARM64.
# Every section prints to the log and to $Out\probe.log.
#
#   powershell -NoProfile -ExecutionPolicy RemoteSigned -File probe.ps1 -Archive Basket-PLATFORM.zip -Out FOLDER

param(
  [Parameter(Mandatory)] [string] $Archive,
  [Parameter(Mandatory)] [string] $Out
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path -LiteralPath $Out).Path
$Log = Join-Path $Out 'probe.log'
$Started = Get-Date
$Work = Join-Path $(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }) 'probe162'
New-Item -ItemType Directory -Force $Work | Out-Null

function Say([string] $Text = '') {
  Write-Host $Text
  Add-Content -LiteralPath $Log -Value $Text -Encoding UTF8
}

function Section([string] $Title) {
  Say ''
  Say "==== $Title"
}

function Show($Object) {
  Say (($Object | Out-String -Width 220).TrimEnd())
}

function Step([string] $What, [scriptblock] $Block) {
  try {
    & $Block
  } catch {
    Say "FAILED: $What : $($_.Exception.Message)"
  }
}

$Machines = @{ 0x14c = 'x86'; 0x8664 = 'x64'; 0xaa64 = 'ARM64'; 0xa641 = 'ARM64EC'; 0x1c4 = 'ARM' }

# The machine type in a PE file's header.
function Get-Machine([string] $Path) {
  try {
    $stream = [IO.File]::OpenRead($Path)
    try {
      $reader = New-Object IO.BinaryReader($stream)
      [void] $stream.Seek(0x3c, 'Begin')
      $offset = $reader.ReadInt32()
      [void] $stream.Seek($offset, 'Begin')
      if ($reader.ReadUInt32() -ne 0x4550) { return 'not PE' }
      $code = [int] $reader.ReadUInt16()
      if ($Machines.ContainsKey($code)) { return $Machines[$code] }
      return ('0x{0:x}' -f $code)
    } finally {
      $stream.Dispose()
    }
  } catch {
    return "unreadable: $($_.Exception.Message)"
  }
}

function Show-Packages([string] $Label) {
  Say "-- packages $Label"
  Show (Get-AppxPackage | Where-Object { $_.Name -match 'WindowsAppRuntime|WinUI|WindowsAppSDK|Microsoft\.UI\.Xaml|VCLibs|DynamicDependency' } |
      Select-Object Name, Version, Architecture, PackageFullName, InstallLocation, SignatureKind, Status, IsFramework | Format-List)
}

# ---------------------------------------------------------------------
Section 'The computer'
Step 'computer' {
  Say "OS: $([Environment]::OSVersion.VersionString)"
  $nt = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
  Say "Windows: $($nt.ProductName) $($nt.DisplayVersion) build $($nt.CurrentBuild).$($nt.UBR)"
  Say "PROCESSOR_ARCHITECTURE=$env:PROCESSOR_ARCHITECTURE PROCESSOR_ARCHITEW6432=$env:PROCESSOR_ARCHITEW6432 PROCESSOR_IDENTIFIER=$env:PROCESSOR_IDENTIFIER"
  Say "PowerShell $($PSVersionTable.PSVersion) at $PSHOME is $(Get-Machine (Join-Path $PSHOME 'powershell.exe'))"
  $user = [Security.Principal.WindowsIdentity]::GetCurrent()
  Say "Account $($user.Name), administrator: $((New-Object Security.Principal.WindowsPrincipal($user)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
  Say "Session $((Get-Process -Id $PID).SessionId), interactive: $([Environment]::UserInteractive)"
}

Section 'Packages registered before anything is installed'
Step 'packages before' { Show-Packages 'before' }

# ---------------------------------------------------------------------
Section "Microsoft's Windows App Runtime 2.7.0, from NuGet"
$RuntimeUrl = 'https://api.nuget.org/v3-flatcontainer/microsoft.windowsappsdk.runtime/2.7.0/microsoft.windowsappsdk.runtime.2.7.0.nupkg'
$RuntimeSha256 = '326b47f40f051e767bfc83ce99c753c758bbba75a25f0a4febab8cd9ea8b5152'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$nupkg = Join-Path $Work 'runtime.nupkg'
$frameworks = @{}
Step 'download' {
  Invoke-WebRequest -UseBasicParsing -Uri $RuntimeUrl -OutFile $nupkg
  Say "SHA-256 $((Get-FileHash -LiteralPath $nupkg -Algorithm SHA256).Hash) (pinned $RuntimeSha256)"
  $zip = [IO.Compression.ZipFile]::OpenRead($nupkg)
  try {
    Say "-- the package's tools/MSIX entries"
    foreach ($entry in $zip.Entries) {
      if ($entry.FullName -like 'tools/MSIX/*') { Say ('  {0,12}  {1}' -f $entry.Length, $entry.FullName) }
    }
    foreach ($folder in 'win10-arm64', 'win10-x64') {
      $entry = $zip.GetEntry("tools/MSIX/$folder/Microsoft.WindowsAppRuntime.2.msix")
      if ($entry) {
        $file = Join-Path $Work "framework-$folder.msix"
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $file, $true)
        $frameworks[$folder] = $file
      } else {
        Say "no framework package for $folder"
      }
    }
  } finally {
    $zip.Dispose()
  }
}

$lists = @{}
foreach ($folder in $frameworks.Keys) {
  Step "read $folder" {
    $zip = [IO.Compression.ZipFile]::OpenRead($frameworks[$folder])
    try {
      $names = @($zip.Entries | ForEach-Object { $_.FullName })
      $lists[$folder] = $names
      Set-Content -LiteralPath (Join-Path $Out "msix-files-$folder.txt") -Value ($zip.Entries | ForEach-Object { '{0,12}  {1}' -f $_.Length, $_.FullName })
      $manifest = $zip.GetEntry('AppxManifest.xml')
      $target = Join-Path $Out "AppxManifest-$folder.xml"
      [IO.Compression.ZipFileExtensions]::ExtractToFile($manifest, $target, $true)
      Say "-- the framework package of ${folder}: $($names.Count) files"
      [xml] $xml = Get-Content -LiteralPath $target -Raw
      $identity = $xml.SelectSingleNode("//*[local-name()='Identity']")
      Say "  Identity: $($identity.OuterXml)"
      foreach ($node in $xml.SelectNodes("//*[local-name()='ActivatableClass'][@ActivatableClassId='Microsoft.UI.Xaml.Controls.XamlControlsResources']")) {
        $path = $node.ParentNode.SelectSingleNode("*[local-name()='Path']").InnerText
        Say "  XamlControlsResources is served by $path : $($node.OuterXml)"
      }
      foreach ($server in $xml.SelectNodes("//*[local-name()='InProcessServer']")) {
        $path = $server.SelectSingleNode("*[local-name()='Path']").InnerText
        Say ('  server {0} has {1} activatable classes' -f $path, @($server.SelectNodes("*[local-name()='ActivatableClass']")).Count)
      }
    } finally {
      $zip.Dispose()
    }
  }
}

Step 'compare' {
  if ($lists.ContainsKey('win10-arm64') -and $lists.ContainsKey('win10-x64')) {
    Say '-- file names that only one of the two framework packages has (<= arm64 only, => x64 only)'
    $difference = @(Compare-Object $lists['win10-arm64'] $lists['win10-x64'])
    Say "  $($difference.Count) differ"
    $difference | Select-Object -First 80 | ForEach-Object { Say "  $($_.SideIndicator) $($_.InputObject)" }
  }
}

# ---------------------------------------------------------------------
Section 'Registering the arm64 framework package, as check-basket-winui.ps1 does'
Step 'Add-AppxPackage' {
  Add-AppxPackage -Path $frameworks['win10-arm64']
  Say 'Add-AppxPackage returned'
}
Step 'packages after' { Show-Packages 'after Add-AppxPackage' }

Section 'What the registered package holds'
Step 'installed files' {
  foreach ($package in @(Get-AppxPackage -Name 'Microsoft.WindowsAppRuntime.2')) {
    $location = $package.InstallLocation
    Say "-- $($package.PackageFullName) ($($package.Architecture)) at $location"
    Copy-Item -LiteralPath (Join-Path $location 'AppxManifest.xml') -Destination (Join-Path $Out "installed-AppxManifest-$($package.Architecture).xml") -ErrorAction Continue
    $dlls = @(Get-ChildItem -LiteralPath $location -Recurse -Filter '*.dll' -ErrorAction Continue)
    $report = $dlls | ForEach-Object { '{0,-8} {1,12} {2}' -f (Get-Machine $_.FullName), $_.Length, $_.FullName.Substring($location.Length) }
    Set-Content -LiteralPath (Join-Path $Out "installed-dlls-$($package.Architecture).txt") -Value $report
    Say "  $($dlls.Count) DLLs, by machine type:"
    $dlls | Group-Object { Get-Machine $_.FullName } | ForEach-Object { Say "    $($_.Count) are $($_.Name)" }
    foreach ($name in 'Microsoft.UI.Xaml.dll', 'Microsoft.WindowsAppRuntime.dll', 'Microsoft.UI.Windowing.dll', 'CoreMessagingXP.dll', 'Microsoft.Windows.ApplicationModel.Resources.dll') {
      $file = Join-Path $location $name
      if (Test-Path -LiteralPath $file) { Say ('  {0,-8} {1}' -f (Get-Machine $file), $name) } else { Say "  missing   $name" }
    }
    $items = @(Get-ChildItem -LiteralPath $location -Force | Select-Object -ExpandProperty Name)
    Say "  top level ($($items.Count) entries): $($items -join ', ')"
    Say "  PRI files: $((Get-ChildItem -LiteralPath $location -Recurse -Filter '*.pri' | ForEach-Object { $_.FullName.Substring($location.Length) }) -join ', ')"
  }
}

# ---------------------------------------------------------------------
Section 'The built Basket'
$orig = Join-Path $Work 'basket'
$name = [IO.Path]::GetFileNameWithoutExtension($Archive)
Expand-Archive -LiteralPath $Archive -DestinationPath $orig
$app = Join-Path (Join-Path $orig $name) 'Basket.exe'
$folder = Split-Path -Parent $app
Say "Basket.exe is $(Get-Machine $app)"
Step 'Basket files' {
  foreach ($file in 'ruby\bin\ruby.exe', 'ruby\bin\rubyw.exe', 'ruby\bin\x64-ucrt-ruby410.dll', 'ruby\bin\arm64-ucrt-ruby410.dll') {
    $path = Join-Path $folder $file
    if (Test-Path -LiteralPath $path) { Say ('  {0,-8} {1}' -f (Get-Machine $path), $file) }
  }
  Get-ChildItem -LiteralPath $folder -Recurse -Include 'fiddle.so', 'libffi*.dll', 'ruby*.dll' | ForEach-Object { Say ('  {0,-8} {1}' -f (Get-Machine $_.FullName), $_.FullName.Substring($folder.Length)) }
}

# The app's PATH keeps only the system's folders, as Delivery has it.
$system = $env:SystemRoot
$env:PATH = "$system\System32;$system;$system\System32\Wbem;$system\System32\WindowsPowerShell\v1.0"
Remove-Item Env:BASKET_SCREEN -ErrorAction SilentlyContinue
$env:HOME = Join-Path $Work 'home'
New-Item -ItemType Directory -Force $env:HOME | Out-Null
$env:USERPROFILE = $env:HOME

function Start-Basket([string] $Label, [int] $Seconds) {
  $env:APPDATA = Join-Path $Work "appdata-$Label"
  $stdout = Join-Path $Out "$Label.out"
  $stderr = Join-Path $Out "$Label.err"
  $process = Start-Process -FilePath $app -WorkingDirectory $system -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $null = $process.Handle
  if (-not $process.WaitForExit($Seconds * 1000)) {
    Say "$Label : Basket.exe still ran after $Seconds seconds, so it is ended"
    $process.Kill()
    [void] $process.WaitForExit(10000)
  } else {
    Say "$Label : Basket.exe exited with $($process.ExitCode)"
  }
  foreach ($file in $stdout, $stderr) {
    Say "-- $(Split-Path -Leaf $file)"
    if (Test-Path -LiteralPath $file) { Say (Get-Content -LiteralPath $file -Raw) }
  }
}

Section 'Basket as built, which logs why it falls back'
Step 'Basket as built' { Start-Basket 'basket-as-built' 25 }

Section 'Basket with the probe as its main.rb'
Step 'probe' {
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'main.rb') -Destination (Join-Path $folder 'app\main.rb') -Force
  $env:PROBE_OUT = Join-Path $Out 'probe-main.txt'
  Start-Basket 'basket-probe' 90
  Say '-- the probe report'
  if (Test-Path -LiteralPath $env:PROBE_OUT) { Say (Get-Content -LiteralPath $env:PROBE_OUT -Raw) } else { Say '(the probe wrote no report)' }
}

Section "The same main.rb under RubyInstaller's ruby.exe, as ruby main.rb with bundler/setup runs it"
Step 'ruby.exe' {
  $ruby = Join-Path $folder 'ruby\bin\ruby.exe'
  $env:PROBE_OUT = Join-Path $Out 'probe-main-rubyexe.txt'
  $env:BUNDLE_GEMFILE = Join-Path $folder 'app\Gemfile'
  $env:APPDATA = Join-Path $Work 'appdata-rubyexe'
  $stdout = Join-Path $Out 'rubyexe.out'
  $stderr = Join-Path $Out 'rubyexe.err'
  $process = Start-Process -FilePath $ruby -ArgumentList @('-rbundler/setup', (Join-Path $folder 'app\main.rb')) -WorkingDirectory (Join-Path $folder 'app') -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $null = $process.Handle
  if (-not $process.WaitForExit(90000)) {
    Say 'ruby.exe still ran after 90 seconds, so it is ended'
    $process.Kill()
    [void] $process.WaitForExit(10000)
  } else {
    Say "ruby.exe exited with $($process.ExitCode)"
  }
  foreach ($file in $stdout, $stderr) {
    Say "-- $(Split-Path -Leaf $file)"
    if (Test-Path -LiteralPath $file) { Say (Get-Content -LiteralPath $file -Raw) }
  }
  Say '-- the probe report'
  if (Test-Path -LiteralPath $env:PROBE_OUT) { Say (Get-Content -LiteralPath $env:PROBE_OUT -Raw) } else { Say '(the probe wrote no report)' }
  Remove-Item Env:BUNDLE_GEMFILE -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------
Section 'Event logs since the probe began'
foreach ($log in 'Application', 'System', 'Microsoft-Windows-AppModel-Runtime/Admin', 'Microsoft-Windows-AppXDeploymentServer/Operational', 'Microsoft-Windows-TWinUI/Operational') {
  Step "log $log" {
    try {
      $events = @(Get-WinEvent -FilterHashtable @{ LogName = $log; StartTime = $Started } -ErrorAction Stop)
    } catch {
      Say "-- $log : $($_.Exception.Message)"
      return
    }
    Say "-- $log : $($events.Count) events"
    $events | Select-Object -First 80 | ForEach-Object {
      $message = ($_.Message -replace '\s+', ' ')
      if ($message.Length -gt 700) { $message = $message.Substring(0, 700) }
      Say ('{0:HH:mm:ss} id {1} {2} [{3}] {4}' -f $_.TimeCreated, $_.Id, $_.ProviderName, $_.LevelDisplayName, $message)
    }
  }
}

Say ''
Say 'Probe 162 finished'
exit 0
