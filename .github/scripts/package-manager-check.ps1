# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Runs the command a package manager installed, as someone with no Ruby
# would: with a PATH of only Folder and Windows' own folders. It must
# print hello's line, pass on its exit status, and leave no ruby command
# beside it.
#
#   package-manager-check.ps1 -Folder DIR -Platform RUBY_PLATFORM

param(
  [Parameter(Mandatory)][string]$Folder,
  [Parameter(Mandatory)][string]$Platform
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Fail($message) {
  Write-Host "::error::$message"
  exit 1
}

$system = $env:SystemRoot
$env:PATH = "$Folder;$system\System32;$system;$system\System32\Wbem;$system\System32\WindowsPowerShell\v1.0"

& where.exe ruby *> $null
if ($LASTEXITCODE -eq 0) { Fail "a ruby command is on PATH, in $(& where.exe ruby)" }

$output = (& hello | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { Fail "hello exited with $LASTEXITCODE" }
Write-Host $output
if ($output -notmatch "^Hello from Ruby \d+\.\d+\.\d+ on $([regex]::Escape($Platform))$") { Fail "hello printed: $output" }

& hello 3 *> $null
if ($LASTEXITCODE -ne 3) { Fail "hello 3 exited with $LASTEXITCODE" }
