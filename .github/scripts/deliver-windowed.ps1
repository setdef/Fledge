# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Delivery of a windowed app (ADR 008) on Windows: unpacks what fledge
# build wrote for examples/windowed_app, checks the identity Windows reads
# from the program with Windows' own means, and starts it as Explorer
# would, with no Ruby anywhere it can reach.
#
#   pwsh -NoProfile -File deliver-windowed.ps1 -Archive ARCHIVE
#
# ARCHIVE is "Hello Window-x64-mingw-ucrt.zip". The program must be a GUI
# program (PE subsystem 2), carry the version information fledge.yml
# says, which (Get-Item).VersionInfo reads as Explorer and Task Manager
# do, and an icon, which Windows extracts as Explorer does. Started with
# Start-Process -Wait, through the shell as a double-click starts it, it
# writes a report of what it ran on, which must say it has no console and
# that its AppUserModelID is the identifier, and exits with the status it
# is given. Nothing here may need Ruby.

param(
  [Parameter(Mandatory)] [string] $Archive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$appName = 'Hello Window'
$identifier = 'com.setdef.fledge.HelloWindow'

function Fail([string] $message) {
  Write-Host "::error::Delivery (windowed): $message"
  exit 1
}

function Expect([string] $Label, $Actual, $Expected) {
  if ($Actual -cne $Expected) { Fail "$Label is '$Actual', not '$Expected'" }
  Write-Host "ok: $Label is $Expected"
}

$Archive = (Resolve-Path -LiteralPath $Archive).Path
$name = [IO.Path]::GetFileNameWithoutExtension($Archive)
$drive = if (Test-Path 'D:\') { 'D:\' } else { $env:RUNNER_TEMP }
$place = Join-Path (Join-Path $drive 'Fledge windowed') "h$([char]0xE9)llo w$([char]0xF6)rld"
New-Item -ItemType Directory -Force $place | Out-Null
Expand-Archive -LiteralPath $Archive -DestinationPath $place
$root = Join-Path $place $name
$app = Join-Path $root "$appName.exe"
if (-not (Test-Path -LiteralPath $app -PathType Leaf)) { Fail "$app is missing after unpacking $Archive" }

$bytes = [IO.File]::ReadAllBytes($app)
$subsystem = [BitConverter]::ToUInt16($bytes, [BitConverter]::ToInt32($bytes, 0x3C) + 24 + 68)
Expect 'the PE subsystem' $subsystem 2

$info = (Get-Item -LiteralPath $app).VersionInfo
Expect 'FileDescription' $info.FileDescription $appName
Expect 'ProductName' $info.ProductName $appName
Expect 'InternalName' $info.InternalName $appName
Expect 'OriginalFilename' $info.OriginalFilename "$appName.exe"
Expect 'CompanyName' $info.CompanyName 'setdef'
Expect 'LegalCopyright' $info.LegalCopyright "$([char]0xA9) 2026 Kerrick Long"
Expect 'FileVersion' $info.FileVersion '1.2.3'
Expect 'ProductVersion' $info.ProductVersion '1.2.3'
Expect 'the file version numbers' "$($info.FileMajorPart).$($info.FileMinorPart).$($info.FileBuildPart).$($info.FilePrivatePart)" '1.2.3.0'

# The icon Explorer shows: how many icon groups the program holds, and
# the icon itself, whose middle is the white of the example's bird.
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace Fledge -Name Shell -MemberDefinition @'
[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
public static extern uint ExtractIconExW(string file, int index, System.IntPtr[] large, System.IntPtr[] small, uint count);
'@
Expect 'the number of icons' ([Fledge.Shell]::ExtractIconExW($app, -1, $null, $null, 0)) 1
$pixel = [Drawing.Icon]::ExtractAssociatedIcon($app).ToBitmap().GetPixel(12, 20)
if ($pixel.R -lt 200 -or $pixel.G -lt 200 -or $pixel.B -lt 200) { Fail "the icon is not the app's: its pixel at (12, 20) is $pixel" }
Write-Host "ok: the icon is the app's ($pixel at (12, 20))"

# The runner has Rubies; the app's PATH keeps only Windows' own folders.
$system = $env:SystemRoot
$env:PATH = "$system\System32;$system;$system\System32\Wbem;$system\System32\WindowsPowerShell\v1.0"
if (Get-Command ruby -ErrorAction SilentlyContinue) { Fail "Get-Command still finds a Ruby on $env:PATH" }

$report = Join-Path $env:RUNNER_TEMP 'windowed report.json'
$process = Start-Process -FilePath $app -ArgumentList "`"$report`"", '4' -WorkingDirectory $system -Wait -PassThru
Expect 'the exit status' $process.ExitCode 4
$facts = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
Expect "the report's Ruby" $facts.ruby '4.0.9'
Expect "the report's platform" $facts.platform 'x64-mingw-ucrt'
Expect "the report's program" $facts.program 'main.rb'
Expect 'whether it had a console' $facts.console $false
Expect 'its AppUserModelID' $facts.app_user_model_id $identifier

Write-Host "Delivered: $appName, windowed"
