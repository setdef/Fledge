# Probe 162 (a spike, never for trunk): a WinUI 3 app in C#, with no Ruby,
# built and run natively and under emulation on Windows on ARM64.
param([Parameter(Mandatory)] [string] $Out)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path -LiteralPath $Out).Path
$Log = Join-Path $Out 'probe-cs.log'
$Work = Join-Path $(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }) 'probe162cs'
New-Item -ItemType Directory -Force $Work | Out-Null
function Say([string] $Text = '') { Write-Host $Text; Add-Content -LiteralPath $Log -Value $Text -Encoding UTF8 }
function Show($Object) { Say (($Object | Out-String -Width 220).TrimEnd()) }
function Run([string] $Label, [scriptblock] $Block) {
  Say "-- $Label"
  try { $text = (& $Block 2>&1 | Out-String -Width 220).TrimEnd(); Say $text; Say "   (exit code $LASTEXITCODE)" } catch { Say "FAILED: $($_.Exception.Message)" }
}

Say '==== Tools the image has'
Run 'dotnet --list-sdks' { dotnet --list-sdks }
Run 'dotnet --list-runtimes' { dotnet --list-runtimes }
Run 'dotnet --info' { dotnet --info }
Run 'Visual Studio installations' { & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -all -products * -property installationPath }
Run 'dotnet workloads' { dotnet workload list }

Say ''
Say '==== The pinned 2.7.0 runtime, both framework packages'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$url = 'https://api.nuget.org/v3-flatcontainer/microsoft.windowsappsdk.runtime/2.7.0/microsoft.windowsappsdk.runtime.2.7.0.nupkg'
$sha = '326b47f40f051e767bfc83ce99c753c758bbba75a25f0a4febab8cd9ea8b5152'
$nupkg = Join-Path $Work 'runtime.nupkg'
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $nupkg
$have = (Get-FileHash -LiteralPath $nupkg -Algorithm SHA256).Hash
Say "SHA-256 $have (pinned $sha)"
foreach ($pair in @(@('arm64', 'win10-arm64', 'Arm64'), @('x64', 'win10-x64', 'X64'))) {
  $folder = $pair[1]; $arch = $pair[2]
  $installed = @(Get-AppxPackage -Name 'Microsoft.WindowsAppRuntime.2' | Where-Object { $_.Architecture -eq $arch -and $_.Version -ge [version] '2.7.0.0' })
  if ($installed.Count -gt 0) { Say "$arch 2.7 is registered already"; continue }
  $zip = [IO.Compression.ZipFile]::OpenRead($nupkg)
  try {
    $file = Join-Path $Work "framework-$folder.msix"
    [IO.Compression.ZipFileExtensions]::ExtractToFile($zip.GetEntry("tools/MSIX/$folder/Microsoft.WindowsAppRuntime.2.msix"), $file, $true)
  } finally { $zip.Dispose() }
  try { Add-AppxPackage -Path $file; Say "registered the $arch framework package" } catch { Say "Add-AppxPackage of $arch failed: $($_.Exception.Message)" }
}
Show (Get-AppxPackage -Name 'Microsoft.WindowsAppRuntime.2' | Select-Object Name, Version, Architecture | Format-Table)

Say ''
Say '==== Build and run'
foreach ($arch in 'ARM64', 'x64') {
  $rid = if ($arch -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
  $dir = Join-Path $Work "src-$arch"
  New-Item -ItemType Directory -Force $dir | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Probe.csproj'), (Join-Path $PSScriptRoot 'Program.cs') -Destination $dir
  $publish = Join-Path $Work "bin-$arch"
  Run "dotnet publish for $rid" { dotnet publish (Join-Path $dir 'Probe.csproj') -c Release -r $rid -p:Platform=$arch --self-contained false -o $publish }
  $exe = Join-Path $publish 'Probe.exe'
  if (-not (Test-Path -LiteralPath $exe)) { Say "no Probe.exe for $arch"; continue }
  $env:PROBE_OUT = Join-Path $Out "report-$arch.txt"
  $stdout = Join-Path $Out "run-$arch.out"; $stderr = Join-Path $Out "run-$arch.err"
  $p = Start-Process -FilePath $exe -WorkingDirectory $publish -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $null = $p.Handle
  if (-not $p.WaitForExit(90000)) { Say "$arch still ran after 90 seconds, so it is ended"; $p.Kill() } else { Say "$arch exited with $($p.ExitCode)" }
  foreach ($f in $stdout, $stderr, $env:PROBE_OUT) { Say "-- $(Split-Path -Leaf $f)"; if (Test-Path -LiteralPath $f) { Say (Get-Content -LiteralPath $f -Raw) } }
}
exit 0
