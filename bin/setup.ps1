# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# bin/setup for Windows: run it from PowerShell, as
#   powershell -NoProfile -ExecutionPolicy Bypass -File bin\setup.ps1
# It does what bin/setup does, and takes Ruby, as bin/setup does, from
# mise.toml: it installs no Ruby through winget or RubyInstaller.

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# A native command's failure does not stop a script by itself.
function Invoke-Checked {
  param([string]$Command, [string[]]$Arguments)
  Write-Host "+ $Command $($Arguments -join ' ')"
  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$Command $($Arguments -join ' ') failed with status $LASTEXITCODE"
  }
}

if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("mise isn't installed. Please install it to continue: https://mise.jdx.dev")
  exit 1
}

# On a CI-like machine (CI is set, as GitHub's runners and other CI
# systems set it) the gems, and the Bundler the lockfile names, go into
# the workspace, so that runs sharing one Ruby never write its gem
# folder at once. A BUNDLE_PATH the environment already names (CI's
# cached folder) wins. On a contributor's computer nothing changes.
$workspaceBundle = $false
if ($env:CI -and -not $env:BUNDLE_PATH) {
  $env:BUNDLE_PATH = Join-Path $PWD.Path "vendor\bundle"
  $workspaceBundle = $true
}

# Ruby, the REUSE tool, actionlint, and shellcheck, pinned in mise.toml
Invoke-Checked mise @("install")
# Later commands, such as bundle exec rake, find the workspace's gems
# through .bundle/config, which git ignores.
if ($workspaceBundle) {
  Invoke-Checked mise @("x", "--", "bundle", "config", "set", "--local", "path", $env:BUNDLE_PATH)
}
Invoke-Checked mise @("x", "--", "bundle", "install")
Invoke-Checked mise @("x", "--", "pre-commit", "install")
Invoke-Checked mise @("x", "--", "bundle", "exec", "rake", "rdoc")
