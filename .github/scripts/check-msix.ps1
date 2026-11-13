# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Checks windowed_app's MSIX package on a contributor's Windows computer,
# with no administrator: builds examples/windowed_app with the runtime in
# RUNTIMES (bundle exec rake runtime, or one CI built), once unsigned and
# once signed with a test certificate made for this run in the current
# user's store, whose subject is the example's msix_publisher; checks
# what each package holds, and that Windows refuses both, the signed one
# because its certificate is trusted nowhere (deliver-msix.ps1
# -UntrustedOnly); and removes the certificate again.
#
# What it cannot prove: that Windows installs the signed package, and
# that the app runs from it. Windows takes a sideloaded package only
# when its certificate is trusted machine-wide, which needs an
# administrator; the current user's TrustedPeople store is not enough
# (0x800B0109). CI's Delivery proves the install, as administrator.
#
#   pwsh -NoProfile -File .github/scripts/check-msix.ps1 [-Runtimes tmp/runtime] [-Work tmp/msix-check]
#
# Run it from the repository's root, after bundle install. It needs the
# Windows SDK's MakeAppx and signtool, which mise.toml's
# http:windows-sdk-buildtools puts on PATH.

param(
  [string] $Runtimes = 'tmp/runtime',
  [string] $Work = 'tmp/msix-check'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string] $message) {
  Write-Host "::error::MSIX check: $message"
  exit 1
}

$platform = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64-mingw-ucrt' } else { 'x64-mingw-ucrt' }
$Work = [IO.Path]::GetFullPath($Work)
Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Work | Out-Null
$env:FLEDGE_RUNTIME_DIR = [IO.Path]::GetFullPath($Runtimes)

$made = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=Fledge Test Signing' `
  -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddDays(1)
$certificate = Join-Path $Work 'certificate.cer'
Export-Certificate -Cert $made -FilePath $certificate | Out-Null
Write-Host "Made Fledge Test Signing, $($made.Thumbprint), in Cert:\CurrentUser\My"

try {
  bundle exec ruby -I lib exe/fledge build -o (Join-Path $Work 'dist') examples/windowed_app
  if ($LASTEXITCODE -ne 0) { Fail 'the unsigned build failed' }
  bundle exec ruby -I lib exe/fledge build --sign $made.Thumbprint -o (Join-Path $Work 'signed') examples/windowed_app
  if ($LASTEXITCODE -ne 0) { Fail 'the signed build failed' }

  pwsh -NoProfile -File (Join-Path $PSScriptRoot 'deliver-msix.ps1') `
    -Package (Join-Path $Work "dist/Hello Window-$platform.msix") `
    -Signed (Join-Path $Work "signed/Hello Window-$platform.msix") `
    -Certificate $certificate -UntrustedOnly -Work $Work
  if ($LASTEXITCODE -ne 0) { Fail 'the packages are not as they should be' }
} finally {
  Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($made.Thumbprint)" -ErrorAction SilentlyContinue
}

Write-Host 'Checked: the MSIX packages built, hold what they should, and are refused where Windows should refuse them'
