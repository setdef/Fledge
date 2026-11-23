# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of a server (examples/file_drop, Drop, a file drop for the
# computers and phones on a network) on Windows, as deliver-server.sh
# delivers it on macOS and Linux: unpacks ARCHIVE, Drop-PLATFORM.zip, and
# runs Drop.exe in a console of its own, as a person opens it, with a
# PATH of only Windows' own folders and HOME a fresh folder, and checks
# that:
#
#   - it prints the address other computers open, and a password;
#   - another process reaches it at that address, which is this
#     computer's own private IPv4 address, not loopback, wherever the
#     computer has one (where it has none, Drop prints localhost, and
#     the script says that it reached loopback only);
#   - it refuses a request without the password with 401;
#   - a file sent as its form sends it arrives in HOME\Drop byte for
#     byte, and a second client, as another device would, finds it
#     listed and fetches the same bytes;
#   - Ctrl-C, which GenerateConsoleCtrlEvent sends to every program on
#     the console, as the console does when a person types it, stops it
#     with status 0, and it printed nothing on standard error;
#   - the app's folder holds the same files after as before.
#
# Each request goes to an address of this computer: none leaves it.
#
#   pwsh -NoProfile -File deliver-server.ps1 -Archive Drop-x64-mingw-ucrt.zip [-Work FOLDER]
#   pwsh -NoProfile -File deliver-server.ps1 -Reference RUBY.EXE,MAIN_RB [-Work FOLDER]
#
# With -Reference, it runs MAIN_RB with RUBY.EXE in place of the app,
# under bundle exec's environment as the caller set it, and expects
# exactly the same. -Work is the folder it unpacks in, RUNNER_TEMP or
# the temporary folder by default. -Port sets another port than 4567,
# Sinatra's.
#
# -Inner is how the script runs itself in a new console; it is not for
# callers. PowerShell's variables ignore case, so no variable here shares
# a parameter's name.

param(
  [string] $Archive,
  [string[]] $Reference,
  [string] $Work = $(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }),
  [int] $Port = 4567,
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

# A file's name with a space and letters beyond ASCII, and its path in a
# link.
$sentName = "$([char]0xC9)t$([char]0xE9) report.bin"
$sentPath = '/files/%C3%89t%C3%A9%20report.bin'

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
  function Report([string] $line) { Add-Content -LiteralPath $results -Value $line -Encoding utf8 }

  $command = @(Get-Content -LiteralPath (Join-Path $folder 'command.txt') -Encoding utf8)
  $system = $env:SystemRoot
  $env:PATH = "$system\System32;$system;$system\System32\Wbem"
  $env:HOME = Join-Path $folder 'home'
  $arguments = @($command | Select-Object -Skip 1 | ForEach-Object { Quote $_ }) + @('-p', $Port)
  $out = Join-Path $folder 'server.out'
  $server = Start-Process -FilePath $command[0] -ArgumentList $arguments -NoNewWindow -PassThru -WorkingDirectory $system `
    -RedirectStandardOutput $out -RedirectStandardError (Join-Path $folder 'server.err')
  $null = $server.Handle
  for ($tick = 0; -not (Select-String -LiteralPath $out -SimpleMatch 'Press Ctrl-C to stop.' -Quiet -ErrorAction SilentlyContinue); $tick++) {
    if ($server.HasExited) { throw "it ended with $($server.ExitCode) before it printed its address" }
    if ($tick -ge 300) { throw 'it did not print its address within 30 seconds' }
    Start-Sleep -Milliseconds 100
  }
  $printed = Get-Content -LiteralPath $out -Encoding utf8
  $url = @($printed | Where-Object { $_ -match '^  (http://\S+/)$' } | ForEach-Object { $Matches[1] })[0]
  $password = @($printed | Where-Object { $_ -match '^and sign in with the password ([a-z0-9]+) \(any user name\)\.$' } | ForEach-Object { $Matches[1] })[0]
  $origin = $url.TrimEnd('/')
  Report "address $(if ($url -like 'http://localhost:*') { 'loopback' } elseif ($url -like 'http://127.*') { $url } else { 'private' })"

  # The status of a request, which Invoke-WebRequest throws for any but
  # success; 0 when nothing answered.
  function Status([scriptblock] $request) {
    try { [int](& $request).StatusCode }
    catch {
      if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
    }
  }
  for ($tick = 0; ($code = Status { Invoke-WebRequest -Uri $url -TimeoutSec 5 }) -eq 0; $tick++) {
    if ($tick -ge 60) { break }
    Start-Sleep -Milliseconds 500
  }
  Report "without password $code"

  $headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("anyone:$password")) }
  $bytes = [byte[]]::new(4096)
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  [IO.File]::WriteAllBytes((Join-Path $folder 'sent.bin'), $bytes)
  $boundary = 'DeliveryOfDrop'
  $utf8 = [Text.UTF8Encoding]::new($false)
  $form = [IO.MemoryStream]::new()
  $head = $utf8.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"files[]`"; filename=`"$sentName`"`r`nContent-Type: application/octet-stream`r`n`r`n")
  $tail = $utf8.GetBytes("`r`n--$boundary--`r`n")
  $form.Write($head, 0, $head.Length); $form.Write($bytes, 0, $bytes.Length); $form.Write($tail, 0, $tail.Length)
  $sent = Status {
    Invoke-WebRequest -Uri $url -Method Post -Body $form.ToArray() -ContentType "multipart/form-data; boundary=$boundary" `
      -Headers ($headers + @{ Origin = $origin }) -PreserveAuthorizationOnRedirect
  }
  Report "sent $sent"
  $arrived = Join-Path (Join-Path $env:HOME 'Drop') $sentName
  Report "arrived $((Test-Path -LiteralPath $arrived) -and [Linq.Enumerable]::SequenceEqual($bytes, [IO.File]::ReadAllBytes($arrived)))"
  Report "files $(@(Get-ChildItem -LiteralPath (Join-Path $env:HOME 'Drop')).Count)"

  $page = Invoke-WebRequest -Uri $url -Headers $headers
  $link = '<a href="' + $sentPath + '">' + $sentName + '</a>'
  Report "listed $($page.Content.Contains($link))"
  $fetched = Join-Path $folder 'fetched.bin'
  Invoke-WebRequest -Uri "$origin$sentPath" -Headers $headers -OutFile $fetched
  Report "fetched $([Linq.Enumerable]::SequenceEqual($bytes, [IO.File]::ReadAllBytes($fetched)))"

  # Sends this console's Ctrl-C, which this process ignores while it is
  # sent.
  [void][Fledge.ServerConsole]::SetConsoleCtrlHandler([IntPtr]::Zero, $true)
  if (-not [Fledge.ServerConsole]::GenerateConsoleCtrlEvent(0, 0)) { throw [ComponentModel.Win32Exception]::new() }
  $stopped = $server.WaitForExit(10000)
  [void][Fledge.ServerConsole]::SetConsoleCtrlHandler([IntPtr]::Zero, $false)
  if (-not $stopped) { $server.Kill(); throw 'it did not stop within 10 seconds of Ctrl-C' }
  Report "exit $($server.ExitCode)"
  exit 0
}

$folder = Join-Path $Work "server-$PID"
New-Item -ItemType Directory -Force (Join-Path $folder 'home') | Out-Null

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
  $command = @(Join-Path $app 'Drop.exe')
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
Write-Host '--- stdout'
Get-Content -LiteralPath (Join-Path $folder 'server.out') -Encoding utf8 -ErrorAction SilentlyContinue
Write-Host '--- stderr'
Get-Content -LiteralPath (Join-Path $folder 'server.err') -Encoding utf8 -ErrorAction SilentlyContinue
if ($results -contains 'address loopback') {
  Write-Host "::notice::Delivery (server): this computer has no private IPv4 address, so the client reached $label on loopback only"
  $results = @($results | ForEach-Object { if ($_ -eq 'address loopback') { 'address private' } else { $_ } })
}
$expected = @('address private', 'without password 401', 'sent 200', 'arrived True', 'files 1', 'listed True', 'fetched True', 'exit 0')
if ($console.ExitCode -ne 0 -or (Compare-Object $expected $results -SyncWindow 0)) {
  Fail "$label answered '$($results -join '; ')', not '$($expected -join '; ')'"
}
Write-Host "ok: $label refused a request without its password, kept the file sent to it in HOME\Drop byte for byte, listed it and gave it back, and stopped on Ctrl-C with 0"

$first = (Get-Content -LiteralPath (Join-Path $folder 'server.out') -Encoding utf8)[0]
$shared = "Drop is sharing $((Join-Path $folder 'home').Replace('\', '/'))/Drop"
if ($first -cne $shared) { Fail "$label printed '$first', not '$shared'" }
if ((Get-Item -LiteralPath (Join-Path $folder 'server.err')).Length -ne 0) { Fail "$label wrote to standard error" }
Write-Host 'ok: it shared the Drop folder of the home folder, and wrote nothing to standard error'
if ($app) {
  $after = @(Get-ChildItem -LiteralPath $app -Recurse -Force | ForEach-Object FullName)
  $added = @(Compare-Object $before $after | ForEach-Object InputObject)
  if ($added) { Fail "$label changed its own folder: $($added -join ', ')" }
  Write-Host 'ok: the app wrote nothing in its own folder'
}
