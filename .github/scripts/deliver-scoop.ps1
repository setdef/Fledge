# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Installs hello with Scoop from the manifest in doc/package_managers.md,
# runs it by its command with no Ruby on PATH, and uninstalls it.
#
#   deliver-scoop.ps1 -Recipes DIR -Platform RUBY_PLATFORM

param(
  [Parameter(Mandatory)][string]$Recipes,
  [Parameter(Mandatory)][string]$Platform
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Fail($message) {
  Write-Host "::error::$message"
  exit 1
}

# Scoop's installer is pinned; the Scoop it installs is today's, as a
# person's is. Runners are administrators, which it refuses unless told.
$installer = Join-Path $env:RUNNER_TEMP 'install-scoop.ps1'
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/ScoopInstaller/Install/1e2f334083d609986d8c8bc9e31ae8e87c39fab4/install.ps1' -OutFile $installer
$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
if ($hash -ne '94F983B190438311E006B957DB7C8422709E0BA62A6C2AC04E278164108F2512') { Fail "Scoop's installer is $hash" }
& $installer -RunAsAdmin
$scoop = Join-Path $env:USERPROFILE 'scoop'
$env:PATH = "$scoop\shims;$env:PATH"

scoop install (Join-Path $Recipes 'scoop\hello.json')
if ($LASTEXITCODE -ne 0) { Fail "scoop install exited with $LASTEXITCODE" }

$shims = @(Get-ChildItem -LiteralPath "$scoop\shims" -Filter '*.exe' | Where-Object { $_.Name -ne 'scoop.exe' })
Write-Host "Shims: $($shims.Name -join ', ')"
if (($shims.Name -join ',') -ne 'hello.exe') { Fail "Scoop made other shims: $($shims.Name -join ', ')" }

& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'package-manager-check.ps1') -Folder "$scoop\shims" -Platform $Platform
if ($LASTEXITCODE -ne 0) { exit 1 }

scoop uninstall hello
if ($LASTEXITCODE -ne 0) { Fail "scoop uninstall exited with $LASTEXITCODE" }
if (Test-Path -LiteralPath "$scoop\apps\hello") { Fail 'uninstalling left the app' }
if (Test-Path -LiteralPath "$scoop\shims\hello.exe") { Fail 'uninstalling left the shim' }
