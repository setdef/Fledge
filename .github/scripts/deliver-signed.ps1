# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of a signed Windows build (ADR 016): examples/hello and
# examples/windowed_app, built with fledge build --sign and CI's test
# certificate (make-test-identity.ps1), checked on a fresh Windows with
# Microsoft's own signtool.
#
#   pwsh -NoProfile -File deliver-signed.ps1 -Hello Hello-x64-mingw-ucrt.zip
#     -Windowed "Hello Window-x64-mingw-ucrt.zip" -Installer "Hello Window-x64-mingw-ucrt-setup.exe"
#     -Certificate certificate.cer
#
# A fresh Windows does not trust the test certificate, so signtool must
# refuse the program at first. Trusted in the computer's root store, as
# a certificate authority's root is on every Windows, every PE file in
# both apps (programs, Ruby's DLLs, its extensions) and the setup program
# must verify as signed by it, with a timestamp; the setup program must
# install the app silently, with the uninstaller it wrote signed too, and
# uninstall it; and the signed program must still run. Nothing here may
# need Ruby.
#
# The same apps signed through fledge build --sign-command (ADR 051) are
# checked the same way after the first run has trusted the certificate,
# with -Trusted, which skips the refusal the first run proved.

param(
  [Parameter(Mandatory)] [string] $Hello,
  [Parameter(Mandatory)] [string] $Windowed,
  [Parameter(Mandatory)] [string] $Installer,
  [Parameter(Mandatory)] [string] $Certificate,
  [switch] $Trusted
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

function Fail([string] $message) {
  Write-Host "::error::Delivery (signed): $message"
  exit 1
}

# Hello-PLATFORM.zip: x64-mingw-ucrt, or aarch64-mingw-ucrt (ADR 035).
$platform = [IO.Path]::GetFileNameWithoutExtension($Hello) -replace '^Hello-', ''
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
$kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
$signtool = Get-ChildItem -LiteralPath $kits -Recurse -Filter signtool.exe | Where-Object { $_.Directory.Name -eq $arch } |
  Sort-Object { [version]$_.Directory.Parent.Name } | Select-Object -Last 1 -ExpandProperty FullName
if (-not $signtool) { Fail "no signtool in $kits" }

# Verify PATHS: signtool verifies each with the default Authenticode
# policy, and says who signed it and when it was stamped.
function Verify([string[]] $paths) {
  $output = & $signtool verify /pa /v @paths 2>&1 | Out-String
  return @{ Status = $LASTEXITCODE; Output = $output }
}

# Whether the file at PATH begins as every PE file does, with DOS's MZ.
function IsPE([string] $path) {
  $stream = [IO.File]::OpenRead($path)
  try { return $stream.ReadByte() -eq 0x4D -and $stream.ReadByte() -eq 0x5A } finally { $stream.Dispose() }
}

$work = Join-Path $env:RUNNER_TEMP "signed-$PID"
New-Item -ItemType Directory -Force $work | Out-Null
foreach ($archive in @($Hello, $Windowed)) { Expand-Archive -LiteralPath $archive -DestinationPath $work }
$program = Join-Path $work "Hello-$platform\Hello.exe"

if (-not $Trusted) {
  $before = Verify @($program)
  if ($before.Status -eq 0) { Fail "signtool trusted the test certificate before this computer did:`n$($before.Output)" }
  Write-Host 'ok: before this computer trusts the test certificate, signtool refuses the program'
}

Import-Certificate -FilePath $Certificate -CertStoreLocation Cert:\LocalMachine\Root | Out-Null

foreach ($name in @("Hello-$platform", "Hello Window-$platform")) {
  $folder = Join-Path $work $name
  $code = @(Get-ChildItem -LiteralPath $folder -Recurse -File | Where-Object { $_.Extension -in '.exe', '.dll', '.so' } |
    Where-Object { IsPE $_.FullName } | Select-Object -ExpandProperty FullName)
  if ($code.Count -lt 10) { Fail "only $($code.Count) PE files in $name" }
  $result = Verify $code
  if ($result.Status -ne 0) { Fail "signtool does not verify every PE file in ${name}:`n$($result.Output)" }
  $signed = ([regex]::Matches($result.Output, 'Issued to: Fledge Test Signing')).Count
  $stamped = ([regex]::Matches($result.Output, 'The signature is timestamped')).Count
  if ($signed -lt $code.Count -or $stamped -lt $code.Count) { Fail "not every PE file in $name is signed by the test certificate and timestamped:`n$($result.Output)" }
  Write-Host "ok: signtool verifies all $($code.Count) PE files in $name, signed by the test certificate and timestamped"
}

$result = Verify @($Installer)
if ($result.Status -ne 0 -or $result.Output -notmatch 'Issued to: Fledge Test Signing') { Fail "signtool does not verify the setup program:`n$($result.Output)" }
Write-Host 'ok: signtool verifies the setup program'

$system = $env:SystemRoot
$env:PATH = "$system\System32;$system;$system\System32\Wbem;$system\System32\WindowsPowerShell\v1.0"
$out = & $program
if ($LASTEXITCODE -ne 0 -or $out -notlike "Hello from Ruby 4.0.9 on $platform") { Fail "the signed Hello.exe printed '$out', exit $LASTEXITCODE" }
Write-Host "ok: the signed Hello.exe ran: $out"

$installed = Join-Path $env:LOCALAPPDATA 'Programs\Hello Window'
$process = Start-Process -FilePath $Installer -ArgumentList '/S' -Wait -PassThru
if ($process.ExitCode -ne 0) { Fail "the silent install exited $($process.ExitCode)" }
$result = Verify @((Join-Path $installed 'uninstall.exe'), (Join-Path $installed 'Hello Window.exe'))
if ($result.Status -ne 0) { Fail "signtool does not verify the installed program and its uninstaller:`n$($result.Output)" }
Write-Host 'ok: signtool verifies the installed program and the uninstaller the setup program wrote'
$process = Start-Process -FilePath (Join-Path $installed 'uninstall.exe') -ArgumentList '/S' -Wait -PassThru
if ($process.ExitCode -ne 0) { Fail "the silent uninstall exited $($process.ExitCode)" }
for ($tick = 0; $tick -lt 100 -and (Test-Path -LiteralPath $installed); $tick++) { Start-Sleep -Milliseconds 200 }
if (Test-Path -LiteralPath $installed) { Fail "$installed is still there after uninstalling" }
Write-Host 'ok: the signed uninstaller removed the app'

Write-Host 'Delivered: the signed Windows apps'
