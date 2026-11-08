# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Packs the Chocolatey package in doc/package_managers.md, installs it
# from that local package, runs hello by its command with no Ruby on
# PATH, and uninstalls it.
#
#   deliver-chocolatey.ps1 -Recipes DIR -Platform RUBY_PLATFORM

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

$bin = "$env:ChocolateyInstall\bin"
$package = Join-Path $Recipes 'chocolatey'
Set-Location -LiteralPath $package
choco --version
choco pack hello.nuspec
if ($LASTEXITCODE -ne 0) { Fail "choco pack exited with $LASTEXITCODE" }

$before = @(Get-ChildItem -LiteralPath $bin -Filter '*.exe').Name
choco install hello --source . --yes --no-progress
if ($LASTEXITCODE -ne 0) { Fail "choco install exited with $LASTEXITCODE" }

$added = @(@(Get-ChildItem -LiteralPath $bin -Filter '*.exe').Name | Where-Object { $before -notcontains $_ })
Write-Host "New shims: $($added -join ', ')"
if (($added -join ',') -ne 'Hello.exe') { Fail "Chocolatey made other shims: $($added -join ', ')" }

& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'package-manager-check.ps1') -Folder $bin -Platform $Platform
if ($LASTEXITCODE -ne 0) { exit 1 }

choco uninstall hello --yes --no-progress
if ($LASTEXITCODE -ne 0) { Fail "choco uninstall exited with $LASTEXITCODE" }
if (Test-Path -LiteralPath "$env:ChocolateyInstall\lib\hello") { Fail 'uninstalling left the app' }
if (Test-Path -LiteralPath "$bin\Hello.exe") { Fail 'uninstalling left the shim' }
