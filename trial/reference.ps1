# Runs the Lota trial's windowed game as its developer runs it, under
# bundle exec on the build computer's own Ruby, with no Fledge in the
# way: on Windows' own OpenGL, then with Mesa's software OpenGL and Vulkan beside
# ruby.exe, as the app had it beside its program. What it shows tells a
# failure of the app from one of the game or the computer.
#
#   pwsh -NoProfile -File reference.ps1 -Project PROJECT -Results RESULTS -Mesa MESA

param(
  [Parameter(Mandatory)] [string] $Project,
  [Parameter(Mandatory)] [string] $Results,
  [Parameter(Mandatory)] [string] $Mesa
)

. (Join-Path $PSScriptRoot 'helpers.ps1')

$ruby = (Get-Command ruby).Source
$bin = Split-Path -Parent $ruby
Write-Host "ruby: $ruby"
$environment = @{}
foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) { $environment[$entry.Key] = $entry.Value }
$environment['BUNDLE_GEMFILE'] = Join-Path $Project 'Gemfile'
$environment['RUBYOPT'] = '-rbundler/setup'
$environment['ALSOFT_DRIVERS'] = 'null'
$main = Join-Path $Project 'main.rb'

$null = Run-App 'reference-quiet' $ruby $environment @($main, 'quiet')
$null = Run-App 'reference-window-windows-opengl' $ruby $environment @($main) 2.5 60
Collect-Frame 'reference-window-windows-opengl'

$copied = @()
foreach ($dll in Get-ChildItem -LiteralPath $Mesa -File) {
  $target = Join-Path $bin $dll.Name
  if (Test-Path -LiteralPath $target) { Write-Host "kept Ruby's own $($dll.Name)"; continue }
  Copy-Item -LiteralPath $dll.FullName -Destination $target
  $copied += $target
}
Section 'whether the OpenGL DLLs load here'
Test-Load @((Join-Path $env:SystemRoot 'System32\opengl32.dll'), (Join-Path $bin 'opengl32.dll'), (Join-Path $bin 'libgallium_wgl.dll'))
$llvmpipe = $environment.Clone()
$llvmpipe['GALLIUM_DRIVER'] = 'llvmpipe'
$null = Run-App 'reference-window-mesa-llvmpipe' $ruby $llvmpipe @($main) 2.5 90
Collect-Frame 'reference-window-mesa-llvmpipe'
$lavapipe = $environment.Clone()
$manifest = Join-Path $bin 'lvp_icd.json'
$lavapipe['VK_DRIVER_FILES'] = $manifest
$lavapipe['VK_ICD_FILENAMES'] = $manifest
$lavapipe['LOTA_TRIAL_RENDERERS'] = 'vulkan'
$null = Run-App 'reference-window-mesa-lavapipe' $ruby $lavapipe @($main) 2.5 90
Collect-Frame 'reference-window-mesa-lavapipe'
$copied | ForEach-Object { Remove-Item -LiteralPath $_ }

Section 'statuses'
Get-Content -LiteralPath $statuses | Write-Host
