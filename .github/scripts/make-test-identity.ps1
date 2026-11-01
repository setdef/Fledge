# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Makes a code signing certificate for CI on Windows (ADR 016): a
# self-signed one, made fresh, in the current user's store, where
# signtool /sha1 finds it, and trusted in the computer's root store, so
# signtool can verify what it signs. No CI runner has a certificate a
# certificate authority issued; this proves the signing that does not
# need one.
#
#   pwsh -NoProfile -File make-test-identity.ps1 -Certificate CERTIFICATE.cer
#
# Writes the certificate, without its key, to CERTIFICATE.cer, for
# Delivery to trust on a fresh runner, and FLEDGE_TEST_SIGN_IDENTITY, its
# SHA-1 thumbprint, to $env:GITHUB_ENV.

param(
  [Parameter(Mandatory)] [string] $Certificate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$made = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=Fledge Test Signing' `
  -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddDays(2)
$store = [Security.Cryptography.X509Certificates.X509Store]::new('Root', 'LocalMachine')
$store.Open('ReadWrite')
$store.Add($made)
$store.Close()
Export-Certificate -Cert $made -FilePath $Certificate | Out-Null
Add-Content -LiteralPath $env:GITHUB_ENV -Value "FLEDGE_TEST_SIGN_IDENTITY=$($made.Thumbprint)"
Write-Host "Made Fledge Test Signing, $($made.Thumbprint)"
