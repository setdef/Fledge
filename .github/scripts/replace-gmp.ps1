# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileComment: Adapted from .github/scripts/replace-gmp.ps1 on Fledge's spike/permissive
#   branch (58edf27d27912d062ccfa5c4960533a220c9eb24).

# Shows that whoever receives a Windows app can replace its LGPL library,
# ruby\bin\ruby_builtin_dlls\libgmp-10.dll, as the LGPL asks (LGPL-3.0
# section 4d), and that the app then uses the replacement.
#
#   pwsh -NoProfile -File replace-gmp.ps1 -Archive ARCHIVE -Dll DLL -Version VERSION
#
# ARCHIVE is a built Hello-x64-mingw-ucrt.zip; DLL a libgmp-10.dll built
# some other way (CI cross-builds GNU MP VERSION with llvm-mingw). The app
# prints Integer::GMP_VERSION, which Ruby reads from the GMP it loaded,
# and the SHA-256 of a large product printed in decimal, which takes GMP's
# multiplication and conversion (bignum.c uses GMP past 20 digits of
# BDIGIT). The product must not change; the version must.

param(
  [Parameter(Mandatory)] [string] $Archive,
  [Parameter(Mandatory)] [string] $Dll,
  [Parameter(Mandatory)] [string] $Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string] $message) {
  Write-Host "::error::replace-gmp: $message"
  exit 1
}

$Archive = (Resolve-Path -LiteralPath $Archive).Path
$Dll = (Resolve-Path -LiteralPath $Dll).Path
$place = Join-Path $env:RUNNER_TEMP 'replace-gmp'
New-Item -ItemType Directory -Force $place | Out-Null
Expand-Archive -LiteralPath $Archive -DestinationPath $place
$root = Join-Path $place ([IO.Path]::GetFileNameWithoutExtension($Archive))
$app = Join-Path $root 'Hello.exe'
$gmp = Join-Path $root 'ruby\bin\ruby_builtin_dlls\libgmp-10.dll'
Set-Content -LiteralPath (Join-Path $root 'app\main.rb') -NoNewline -Value @'
require "digest"
n = (3**200_000) * (7**150_000)
puts Integer::GMP_VERSION
puts Digest::SHA256.hexdigest(n.to_s)
'@

$system = $env:SystemRoot
$path = "$system\System32;$system"

function Invoke-Hello {
  $info = [Diagnostics.ProcessStartInfo]::new($app)
  $info.UseShellExecute = $false
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.Environment.Clear()
  $info.Environment['SystemRoot'] = $system
  $info.Environment['PATH'] = $path
  $info.Environment['TEMP'] = $env:RUNNER_TEMP
  $process = [Diagnostics.Process]::Start($info)
  $errors = $process.StandardError.ReadToEndAsync()
  $out = $process.StandardOutput.ReadToEnd()
  $process.WaitForExit()
  if ($process.ExitCode -ne 0) { Fail "Hello.exe exited $($process.ExitCode): $out $($errors.GetAwaiter().GetResult())" }
  $out -split "`r?`n" | Where-Object { $_ -ne '' }
}

$before = @(Invoke-Hello)
Write-Host "RubyInstaller's libgmp-10.dll ($((Get-FileHash $gmp).Hash.Substring(0, 16))): $($before -join ' / ')"
Copy-Item -LiteralPath $Dll -Destination $gmp -Force
$after = @(Invoke-Hello)
Write-Host "Replacement libgmp-10.dll ($((Get-FileHash $gmp).Hash.Substring(0, 16))): $($after -join ' / ')"

if ($before[0] -ne 'GMP 6.3.0') { Fail "the app first reported $($before[0]), not RubyInstaller's GMP 6.3.0" }
if ($after[0] -ne "GMP $Version") { Fail "after the swap the app reported $($after[0]), not GMP ${Version}: it did not load the replacement" }
if ($after[1] -ne $before[1]) { Fail "the replacement GMP computed a different product" }
"| | Integer::GMP_VERSION | SHA-256 of the product |`n|---|---|---|`n| RubyInstaller's DLL | $($before[0]) | ``$($before[1])`` |`n| replacement DLL | $($after[0]) | ``$($after[1])`` |" |
  Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
Write-Host "Replaced libgmp-10.dll; the app loaded GMP $Version and computed the same product."
