# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Installs hello with winget from the manifests in
# doc/package_managers.md, runs it by its command with no Ruby on PATH,
# and uninstalls it.
#
#   deliver-winget.ps1 -Recipes DIR -Platform RUBY_PLATFORM

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

$manifest = Join-Path $Recipes 'winget'
Get-Command winget -ErrorAction SilentlyContinue | Format-List Source, Version
winget --info
if ($LASTEXITCODE -ne 0) { Fail "winget --info exited with $LASTEXITCODE" }
winget settings --enable LocalManifestFiles
if ($LASTEXITCODE -ne 0) { Fail "enabling local manifests exited with $LASTEXITCODE" }
winget validate --manifest $manifest --disable-interactivity
# Warnings exit with 0x8A150028 (a validation warning), not an error: a
# runner's older winget does not know the newest schema's header.
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335192) { Fail "winget validate exited with $LASTEXITCODE" }

winget install --manifest $manifest --accept-package-agreements --accept-source-agreements --disable-interactivity
if ($LASTEXITCODE -ne 0) { Fail "winget install exited with $LASTEXITCODE" }

$links = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
Get-ChildItem -LiteralPath $links | Format-List FullName, LinkType, Target
& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'package-manager-check.ps1') -Folder $links -Platform $Platform
if ($LASTEXITCODE -ne 0) { exit 1 }

winget uninstall --manifest $manifest --accept-source-agreements --disable-interactivity
if ($LASTEXITCODE -ne 0) { Fail "winget uninstall exited with $LASTEXITCODE" }
if (Test-Path -LiteralPath (Join-Path $links 'hello.exe')) { Fail 'uninstalling left the link' }
if (Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages') -Filter 'Example.Hello*' -ErrorAction SilentlyContinue) { Fail 'uninstalling left the app' }
