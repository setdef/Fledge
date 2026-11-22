# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivers the HTTPS probe (test/fixtures/https) on Windows, as
# deliver-https.sh does on macOS and Linux: unpacks ARCHIVE,
# Https-PLATFORM.zip, under a folder named outside ASCII for each case,
# runs Https.exe with Windows' own folders on PATH and nothing else,
# asking the server .github/scripts/https-server.sh runs (through Git's
# bash and openssl, which every Windows runner has), and checks that it
# trusts the server, or refuses it, as RubyInstaller's ruby.exe does
# (doc/contributors/design/runtimes.md, "Certificates"):
#
#   none      the test authority nowhere: refused.
#   variable  in the file SSL_CERT_FILE names: trusted.
#   bundled   added to the CA bundle RubyInstaller's OpenSSL finds beside
#             its DLLs, ruby\lib\ruby\ABI\etc\ssl\cert.pem: trusted.
#   store     in Windows' own store of root authorities: refused, since
#             OpenSSL does not read it. It changes what the computer
#             trusts, so it runs only on GitHub's runners (GITHUB_ACTIONS
#             is true there), and the authority leaves the store after.
#
#   pwsh -NoProfile -File deliver-https.ps1 -Archive ARCHIVE [-Work FOLDER]
#
# WORK is where the apps are unpacked and the server's files are kept:
# RUNNER_TEMP on a runner, and the system's temporary folder elsewhere.

param(
  [Parameter(Mandatory)] [string] $Archive,
  [string] $Work = $(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

function Fail([string] $message) {
  Write-Host "::error::Delivery of the HTTPS probe: $message"
  exit 1
}

$Archive = (Resolve-Path -LiteralPath $Archive).Path
$name = [IO.Path]::GetFileNameWithoutExtension($Archive)
$work = Join-Path $Work "https-$PID"
$server = Join-Path $work 'server'
New-Item -ItemType Directory -Force $server | Out-Null
$bash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
# Elsewhere an MSYS2 bash on PATH; Windows' own bash.exe is WSL's.
if (-not (Test-Path -LiteralPath $bash)) {
  $bash = Get-Command bash -All -ErrorAction SilentlyContinue | Where-Object { $_.Source -notlike "$env:SystemRoot*" } |
    Select-Object -First 1 -ExpandProperty Source
}
if (-not $bash) { Fail "no bash, Git's or on PATH, to run https-server.sh" }
$script = Join-Path $PSScriptRoot 'https-server.sh'
$serverPath = $server -replace '\\', '/'
& $bash $script start $serverPath
if ($LASTEXITCODE -ne 0) { Fail 'https-server.sh did not start' }
$url = (Get-Content -LiteralPath (Join-Path $server 'url') -Raw).Trim()
$authority = Join-Path $server 'ca.pem'

$system = $env:SystemRoot
$path = "$system\System32;$system;$system\System32\Wbem;$system\System32\WindowsPowerShell\v1.0"

# Runs the app with the authority placed as $Case says, from Windows'
# folder, with exactly the environment a desktop gives a program, and
# fails unless it $Expect (trusts or refuses) the server.
function Check([string] $Case, [string] $Expect) {
  $place = Join-Path (Join-Path $work $Case) "h$([char]0xE9)llo w$([char]0xF6)rld"
  New-Item -ItemType Directory -Force $place | Out-Null
  Expand-Archive -LiteralPath $Archive -DestinationPath $place
  $root = Join-Path $place $name
  $app = Join-Path $root 'Https.exe'
  if (-not (Test-Path -LiteralPath $app)) { Fail "$app is not in the archive" }
  $bundle = @(Get-ChildItem -Path (Join-Path $root 'ruby\lib\ruby\*\etc\ssl\cert.pem'))
  if ($bundle.Count -ne 1) { Fail "the app carries $($bundle.Count) ruby\lib\ruby\*\etc\ssl\cert.pem, not one" }
  $environment = @{
    SystemRoot = $system; SystemDrive = $env:SystemDrive; windir = $system; PATH = $path
    USERPROFILE = $env:USERPROFILE; TEMP = $place; TMP = $place
  }
  if ($Case -eq 'variable') { $environment.SSL_CERT_FILE = $authority }
  if ($Case -eq 'bundled') { Add-Content -LiteralPath $bundle[0].FullName -Value (Get-Content -LiteralPath $authority -Raw) -NoNewline }

  $info = [Diagnostics.ProcessStartInfo]::new($app)
  # Arguments rather than ArgumentList, which Windows PowerShell 5.1's
  # .NET Framework lacks, so the script runs under either PowerShell.
  $info.Arguments = '"' + $url + '"'
  $info.UseShellExecute = $false
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
  $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
  $info.WorkingDirectory = $system
  $info.Environment.Clear()
  foreach ($key in $environment.Keys) { $info.Environment[$key] = $environment[$key] }
  $process = [Diagnostics.Process]::Start($info)
  $errors = $process.StandardError.ReadToEndAsync()
  $out = $process.StandardOutput.ReadToEnd()
  $process.WaitForExit()
  $line = $out.Trim()
  $ok = switch ($Expect) {
    'trusts' { $process.ExitCode -eq 0 -and $line.StartsWith('HTTPS to 127.0.0.1: 200, certificates ') }
    'refuses' { $process.ExitCode -eq 1 -and $line.StartsWith('HTTPS to 127.0.0.1: certificate verify failed') }
  }
  if (-not $ok) {
    Write-Host '--- stdout'; Write-Host $out
    Write-Host '--- stderr'; Write-Host $errors.GetAwaiter().GetResult()
    Fail "($Case) the app must say it $Expect the server, but it exited with $($process.ExitCode) and printed '$line'"
  }
  Write-Host "ok ($Case, $Expect): $line"
}

try {
  Check 'none' 'refuses'
  Check 'variable' 'trusts'
  Check 'bundled' 'trusts'
  if ($env:GITHUB_ACTIONS -ne 'true') {
    Write-Host "not tried (store): only on GitHub's runners, since it changes what this computer trusts"
  } else {
    $trusted = Import-Certificate -FilePath $authority -CertStoreLocation Cert:\LocalMachine\Root
    try { Check 'store' 'refuses' }
    finally { Remove-Item -LiteralPath "Cert:\LocalMachine\Root\$($trusted.Thumbprint)" }
  }
} finally {
  & $bash $script stop $serverPath
}
