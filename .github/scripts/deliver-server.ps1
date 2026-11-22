# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of a server (examples/roda_server, Jot, a notes board served
# on 127.0.0.1) on Windows, as deliver-server.sh delivers it on macOS and
# Linux: unpacks ARCHIVE, Jot-PLATFORM.zip, and runs Jot.exe in a console
# of its own, as a person opens it, with a PATH of only Windows' own
# folders, and checks that:
#
#   - it listens on 127.0.0.1 alone, at port 8765, and answers its page;
#   - a note sent as its form sends it is listed on the page, and kept in
#     the person's roaming AppData folder, APPDATA\Jot, not in the app,
#     whose folder holds the same files after as before;
#   - Ctrl-C, which GenerateConsoleCtrlEvent sends to every program on
#     the console, as the console does when a person types it, stops it
#     with status 0, after it says so;
#   - started again, it lists the note it kept, and a second start while
#     it runs says the port is taken and ends with 69 (EX_UNAVAILABLE).
#
# A closed console window ends the server at once, before any ensure
# clause runs, under ruby.exe as in the app (deliver-console.ps1 shows
# it), which is why Jot writes each note as it comes. No request leaves
# the computer.
#
#   pwsh -NoProfile -File deliver-server.ps1 -Archive Jot-x64-mingw-ucrt.zip [-Work FOLDER]
#   pwsh -NoProfile -File deliver-server.ps1 -Reference RUBY.EXE,MAIN_RB [-Work FOLDER]
#
# With -Reference, it runs MAIN_RB with RUBY.EXE in place of the app,
# under bundle exec's environment as the caller set it, and expects
# exactly the same. -Work is the folder it unpacks in, RUNNER_TEMP or
# the temporary folder by default. -Port sets another port than 8765.
#
# -Inner is how the script runs itself in a new console; it is not for
# callers. PowerShell's variables ignore case, so no variable here shares
# a parameter's name.

param(
  [string] $Archive,
  [string[]] $Reference,
  [string] $Work = $(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }),
  [int] $Port = 8765,
  [string] $Inner
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

Add-Type -Namespace Fledge -Name ServerConsole -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleCtrlHandler(IntPtr handler, bool add);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GenerateConsoleCtrlEvent(uint ctrlEvent, uint processGroupId);
'@

function Fail([string] $message) {
  Write-Host "::error::Delivery (server): $message"
  exit 1
}

function Quote([string] $argument) { "`"$argument`"" }

$url = "http://127.0.0.1:$Port"

# Inside the new console: starts the server on it, asks it, ends it with
# Ctrl-C, and writes each result as a line of results.txt for the outer
# run to read. Whatever fails in here, the outer run reads why.
if ($Inner) {
  $folder = $Inner
  $results = Join-Path $folder 'results.txt'
  trap {
    Add-Content -LiteralPath $results -Value "failed: $_" -Encoding utf8
    exit 1
  }
  $command = @(Get-Content -LiteralPath (Join-Path $folder 'command.txt') -Encoding utf8)
  $system = $env:SystemRoot
  $env:PATH = "$system\System32;$system;$system\System32\Wbem"
  $env:APPDATA = Join-Path $folder 'appdata'
  $arguments = @($command | Select-Object -Skip 1 | ForEach-Object { Quote $_ }) + @('--port', $Port, '--no-browser')

  function Start-Server([string] $name) {
    $server = Start-Process -FilePath $command[0] -ArgumentList $arguments -NoNewWindow -PassThru -WorkingDirectory $system `
      -RedirectStandardOutput (Join-Path $folder "$name.out") -RedirectStandardError (Join-Path $folder "$name.err")
    $null = $server.Handle
    for ($tick = 0; $tick -lt 300; $tick++) {
      if (Select-String -LiteralPath (Join-Path $folder "$name.out") -SimpleMatch "Jot is at $url/" -Quiet -ErrorAction SilentlyContinue) { return $server }
      if ($server.HasExited) { throw "$name ended with $($server.ExitCode) before it listened" }
      Start-Sleep -Milliseconds 100
    }
    throw "$name did not say it listened within 30 seconds"
  }

  function Ask([string] $path, [string] $form) {
    if ($form) {
      $page = Invoke-WebRequest -Uri "$url$path" -Method Post -Body $form -ContentType 'application/x-www-form-urlencoded' -Headers @{ Origin = $url }
    } else {
      $page = Invoke-WebRequest -Uri "$url$path"
    }
    $page.Content
  }

  # Sends this console's Ctrl-C, which this process ignores while it is
  # sent. A program inherits that ignoring from the one that starts it,
  # so it ends before the next server starts.
  function Stop-Server($server, [string] $name) {
    [void][Fledge.ServerConsole]::SetConsoleCtrlHandler([IntPtr]::Zero, $true)
    if (-not [Fledge.ServerConsole]::GenerateConsoleCtrlEvent(0, 0)) { throw [ComponentModel.Win32Exception]::new() }
    $stopped = $server.WaitForExit(10000)
    [void][Fledge.ServerConsole]::SetConsoleCtrlHandler([IntPtr]::Zero, $false)
    if (-not $stopped) { $server.Kill(); throw "$name did not stop within 10 seconds of Ctrl-C" }
    Add-Content -LiteralPath $results -Value "$name exit $($server.ExitCode)" -Encoding utf8
  }

  $server = Start-Server 'first'
  $listening = @(Get-NetTCPConnection -State Listen -LocalPort $Port | ForEach-Object { "$($_.LocalAddress):$($_.LocalPort)" })
  Add-Content -LiteralPath $results -Value "listening $($listening -join ' ')" -Encoding utf8
  Add-Content -LiteralPath $results -Value "empty $([bool]((Ask '/') -match '<p>No notes yet\.</p>'))" -Encoding utf8
  $note = "Ask Ana about the $([char]0xE9)t$([char]0xE9) rota"
  $listed = (Ask '/notes' 'text=Ask+Ana+about+the+%C3%A9t%C3%A9+rota').Contains("<li><p>$note</p>")
  Add-Content -LiteralPath $results -Value "listed $listed" -Encoding utf8
  Stop-Server $server 'first'

  $server = Start-Server 'again'
  Add-Content -LiteralPath $results -Value "kept $((Ask '/').Contains("<li><p>$note</p>"))" -Encoding utf8
  $taken = Start-Process -FilePath $command[0] -ArgumentList $arguments -NoNewWindow -PassThru -WorkingDirectory $system `
    -RedirectStandardOutput (Join-Path $folder 'taken.out') -RedirectStandardError (Join-Path $folder 'taken.err')
  $null = $taken.Handle
  # A second server that listens on the taken port, as Windows lets a
  # socket with SO_REUSEADDR do, would never end by itself.
  if ($taken.WaitForExit(15000)) {
    Add-Content -LiteralPath $results -Value "taken exit $($taken.ExitCode)" -Encoding utf8
  } else {
    $taken.Kill()
    Add-Content -LiteralPath $results -Value 'taken did not exit: it listened on the taken port' -Encoding utf8
  }
  Stop-Server $server 'again'
  exit 0
}

$folder = Join-Path $Work "server-$PID"
New-Item -ItemType Directory -Force (Join-Path $folder 'appdata') | Out-Null

if ($Reference) {
  $label = 'ruby.exe main.rb'
  $command = @((Resolve-Path -LiteralPath $Reference[0]).Path, (Resolve-Path -LiteralPath $Reference[1]).Path)
  $app = $null
} else {
  $label = 'the built app'
  $Archive = (Resolve-Path -LiteralPath $Archive).Path
  $name = [IO.Path]::GetFileNameWithoutExtension($Archive)
  Expand-Archive -LiteralPath $Archive -DestinationPath (Join-Path $folder 'apps')
  $app = Join-Path (Join-Path $folder 'apps') $name
  $command = @(Join-Path $app 'Jot.exe')
  $before = @(Get-ChildItem -LiteralPath $app -Recurse -Force | ForEach-Object FullName)
}
Set-Content -LiteralPath (Join-Path $folder 'command.txt') -Value $command -Encoding utf8

# Runs the inner part in a new console, which Start-Process opens for a
# console program, as Explorer does.
$shell = (Get-Process -Id $PID).Path
$console = Start-Process -FilePath $shell -PassThru -ArgumentList '-NoProfile', '-File', (Quote $PSCommandPath),
  '-Inner', (Quote $folder), '-Port', $Port
if (-not $console.WaitForExit(120000)) { Fail "$label's console did not finish within two minutes" }
$results = @(Get-Content -LiteralPath (Join-Path $folder 'results.txt') -Encoding utf8 -ErrorAction SilentlyContinue)
$data = (Join-Path $folder 'appdata').Replace('\', '/') + '/Jot'
foreach ($run in 'first', 'again') {
  Write-Host "--- $run"
  Get-Content -LiteralPath (Join-Path $folder "$run.out"), (Join-Path $folder "$run.err") -ErrorAction SilentlyContinue
}
$expected = @("listening 127.0.0.1:$Port", 'empty True', 'listed True', 'first exit 0', 'kept True', 'taken exit 69', 'again exit 0')
if ($console.ExitCode -ne 0 -or (Compare-Object $expected $results -SyncWindow 0)) {
  Fail "$label answered '$($results -join '; ')', not '$($expected -join '; ')'"
}
Write-Host "ok: $label listened on 127.0.0.1:$Port alone, listed the note sent to it, stopped on Ctrl-C with 0, listed the note again, and refused a taken port with 69"

foreach ($run in 'first', 'again') {
  $out = (Get-Content -LiteralPath (Join-Path $folder "$run.out") -Encoding utf8) -join "`n"
  $said = "Jot is at $url/`nPress Ctrl-C to stop it.`nJot stopped. Your notes are in $data"
  if ($out -cne $said) { Fail "$label ($run) printed '$out', not '$said'" }
  if ((Get-Item -LiteralPath (Join-Path $folder "$run.err")).Length -ne 0) { Fail "$label ($run) wrote to standard error" }
}
if (-not (Select-String -LiteralPath (Join-Path $folder 'taken.err') -SimpleMatch "Jot cannot start: port $Port is in use" -Quiet)) {
  Fail "$label, started on a taken port, did not say so"
}
if (-not (Test-Path -LiteralPath (Join-Path $folder 'appdata\Jot\notes.json'))) { Fail "$label kept no notes.json in APPDATA\Jot" }
Write-Host "ok: it printed its address and where the notes are, and kept them in APPDATA\Jot\notes.json"
if ($app) {
  $after = @(Get-ChildItem -LiteralPath $app -Recurse -Force | ForEach-Object FullName)
  $added = @(Compare-Object $before $after | ForEach-Object InputObject)
  if ($added) { Fail "$label changed its own folder: $($added -join ', ')" }
  Write-Host 'ok: the app wrote nothing in its own folder'
}
