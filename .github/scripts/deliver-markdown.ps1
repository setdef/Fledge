# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of examples/markdown_preview on Windows: its NSIS setup
# program, installed as a person installs it, with nothing of Fledge or
# Ruby on this computer.
#
#   pwsh -NoProfile -File deliver-markdown.ps1 -Installer INSTALLER -Sample SAMPLE -Expected EXPECTED [-Work FOLDER]
#
# INSTALLER is "Markdown Preview-x64-mingw-ucrt-setup.exe", or
# aarch64-mingw-ucrt's. SAMPLE is a Markdown file, and EXPECTED the HTML
# bundle exec ruby bin/md2html printed for it on the Build job. WORK is
# the one folder the script writes in: RUNNER_TEMP on a runner, and the
# system's temporary folder elsewhere.
#
# Installed silently (/S), the app's console program, md2html.exe, must
# be in the folder it was installed in and print EXPECTED for SAMPLE. The
# app must be in the "Open with" list of .md and .markdown files without
# taking their default, and a .md file in a folder whose name has a space
# and a character outside ASCII, opened through the shell with the app's
# ProgID as a double-click on it opens it once the app is the default,
# must start its windowed program with the file's path: it writes the
# preview page into its temporary folder and hands it to the browser,
# here a recorder that BROWSER names. Then the silent uninstaller must
# remove the app and its file associations.

param(
  [Parameter(Mandatory)] [string] $Installer,
  [Parameter(Mandatory)] [string] $Sample,
  [Parameter(Mandatory)] [string] $Expected,
  [string] $Work = $(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$appName = 'Markdown Preview'

function Fail([string] $message) {
  Write-Host "::error::Delivery (markdown_preview): $message"
  exit 1
}

function Expect([string] $Label, $Actual, $Expected) {
  if ($Actual -cne $Expected) { Fail "$Label is '$Actual', not '$Expected'" }
  Write-Host "ok: $Label is $Expected"
}

function WaitFor([scriptblock] $Condition, [string] $What, [int] $Seconds = 60) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  while (-not (& $Condition)) {
    if ((Get-Date) -gt $deadline) { Fail "$What did not happen within $Seconds seconds" }
    Start-Sleep -Milliseconds 500
  }
}

# A file's text as UTF-8, with Windows' line ends made Unix's, since
# Ruby's standard output on Windows writes each "\n" as "\r\n".
function Text([string] $path) {
  [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false)).Replace("`r`n", "`n")
}

Add-Type -Namespace Fledge -Name Shell -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct ShellExecuteInfo {
  public int size; public uint mask; public System.IntPtr window;
  public string verb; public string file; public string parameters; public string directory;
  public int show; public System.IntPtr instance; public System.IntPtr idList; public string className;
  public System.IntPtr classKey; public uint hotKey; public System.IntPtr icon; public System.IntPtr process;
}

[DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool ShellExecuteExW(ref ShellExecuteInfo info);

// Opens file with verb as the shell does, through the ProgID className
// (SEE_MASK_CLASSNAME, 0x1), waiting for the shell to start it
// (SEE_MASK_NOASYNC, 0x100), with no dialog on an error
// (SEE_MASK_FLAG_NO_UI, 0x400), on a single-threaded apartment of its
// own, for at most a minute. Returns null, or why it failed.
public static string Open(string file, string verb, string className) {
  string result = "it did not return within a minute";
  System.Threading.Thread thread = new System.Threading.Thread(() => {
    ShellExecuteInfo info = new ShellExecuteInfo();
    info.size = Marshal.SizeOf(info);
    info.mask = 0x501u;
    info.verb = verb; info.file = file; info.className = className; info.show = 1;
    result = ShellExecuteExW(ref info) ? null : new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()).Message;
  });
  thread.IsBackground = true;
  thread.SetApartmentState(System.Threading.ApartmentState.STA);
  thread.Start();
  thread.Join(60000);
  return result;
}
'@

$Installer = (Resolve-Path -LiteralPath $Installer).Path
$Sample = (Resolve-Path -LiteralPath $Sample).Path
$Expected = (Resolve-Path -LiteralPath $Expected).Path
$folder = Join-Path $env:LOCALAPPDATA "Programs\$appName"
$app = Join-Path $folder "$appName.exe"
$md2html = Join-Path $folder 'md2html.exe'
if (Test-Path -LiteralPath $folder) { Fail "$folder is there before the install" }

# The runner has Rubies; the installer and the app see only Windows'.
$system = $env:SystemRoot
$env:PATH = "$system\System32;$system;$system\System32\WindowsPowerShell\v1.0"
if (Get-Command ruby -ErrorAction SilentlyContinue) { Fail "Get-Command still finds a Ruby on $env:PATH" }

# The defaults of Markdown's extensions before the install, which the
# install must leave as they are: none on a fresh Windows, or another
# app's.
$classes = 'HKCU:\Software\Classes'
function Default([string] $extension) {
  $key = Get-Item -LiteralPath "$classes\$extension" -ErrorAction SilentlyContinue
  if ($key) { $key.GetValue('') } else { $null }
}
$defaults = @{ '.md' = (Default '.md'); '.markdown' = (Default '.markdown') }

$process = Start-Process -FilePath $Installer -ArgumentList '/S' -Wait -PassThru
Expect 'the silent install exit status' $process.ExitCode 0
foreach ($program in @($app, $md2html)) {
  if (-not (Test-Path -LiteralPath $program -PathType Leaf)) { Fail "$program is not installed" }
}
Write-Host "ok: $appName and md2html are installed in $folder"

# md2html, from the installed folder, prints what bundle exec printed.
$out = Join-Path $Work 'md2html.html'
$err = Join-Path $Work 'md2html.err'
$process = Start-Process -FilePath $md2html -ArgumentList "`"$Sample`"" -NoNewWindow -Wait -PassThru `
  -RedirectStandardOutput $out -RedirectStandardError $err
if ($process.ExitCode -ne 0) { Get-Content -LiteralPath $err; Fail "md2html exited with $($process.ExitCode)" }
if ((Get-Item -LiteralPath $err).Length -ne 0) { Get-Content -LiteralPath $err; Fail 'md2html wrote to standard error' }
if ((Text $out) -cne (Text $Expected)) { Fail "md2html printed other HTML than bundle exec: $(Text $out)" }
Write-Host 'ok: md2html prints what bundle exec prints'

# Markdown files, in fledge.yml's file_associations: each extension's
# "Open with" list names one ProgID, whose open command passes the path
# as the program's one argument, and the extension's default is left
# alone.
$command = "`"$app`" `"%1`""
$progId = $null
foreach ($extension in '.md', '.markdown') {
  Expect "the default of $extension" (Default $extension) $defaults[$extension]
  $progIds = @((Get-Item -LiteralPath "$classes\$extension\OpenWithProgids").GetValueNames())
  Expect "$extension's OpenWithProgids, how many" $progIds.Count 1
  if ($progId -and $progIds[0] -cne $progId) { Fail "$extension names $($progIds[0]), and the other extension $progId" }
  $progId = $progIds[0]
}
Expect "$progId's name" (Get-Item -LiteralPath "$classes\$progId").GetValue('') 'Markdown document'
Expect "$progId's command" (Get-Item -LiteralPath "$classes\$progId\shell\open\command").GetValue('') $command

# Opened through the shell, the windowed program writes the preview into
# its temporary folder (Ruby's Dir.tmpdir: TMPDIR, TMP, or TEMP) and
# starts BROWSER with its path: a batch file, which Ruby runs through
# cmd.exe, and which writes the path it is handed where this script reads
# it. The recorder and the temporary folder have ASCII names, since cmd.exe
# reads a batch file in the console's code page.
$recorder = Join-Path $Work 'markdown-recorder'
$temporary = Join-Path $recorder 'tmp'
New-Item -ItemType Directory -Force $temporary | Out-Null
$opened = Join-Path $recorder 'opened.txt'
$browser = Join-Path $recorder 'browser.cmd'
Set-Content -LiteralPath $browser -Encoding ascii -Value "@echo off`r`n> `"$opened`" echo %~1"
$env:BROWSER = $browser
$env:TMPDIR = $temporary
$env:TMP = $temporary
$env:TEMP = $temporary

$documents = Join-Path $Work "Markdown d$([char]0xF6)cs"
New-Item -ItemType Directory -Force $documents | Out-Null
$document = Join-Path $documents 'notes.md'
Copy-Item -LiteralPath $Sample -Destination $document
$failed = [Fledge.Shell]::Open($document, 'open', $progId)
if ($failed) { Fail "the shell could not open $document with ${progId}: $failed" }
WaitFor { Test-Path -LiteralPath $opened } "$appName handing its preview to the browser"
Start-Sleep -Seconds 1
$page = Join-Path $temporary 'markdown-preview\notes.html'
Expect 'the page the browser was handed' ((Get-Content -LiteralPath $opened -Raw).Trim().Replace('/', '\')) $page
$lines = [Collections.Generic.HashSet[string]]::new([string[]] (Text $page).Split("`n"))
$missing = @((Text $Expected).Split("`n") | Where-Object { -not $lines.Contains($_) })
if ($missing.Count -ne 0) { Fail "the preview lacks these lines of the file's HTML: $($missing -join ' / ')" }
Write-Host "ok: the shell opened $document with $appName, which wrote the preview and opened it in the browser"

$process = Start-Process -FilePath (Join-Path $folder 'uninstall.exe') -ArgumentList '/S' -Wait -PassThru
Expect 'the silent uninstall exit status' $process.ExitCode 0
WaitFor { -not (Test-Path -LiteralPath $folder) } "$folder going away" 120
if (Test-Path -LiteralPath "$classes\$progId") { Fail "$classes\$progId is still in the registry" }
# Another app's ProgID may share an extension's list; only this one's must go.
foreach ($extension in '.md', '.markdown') {
  $list = "$classes\$extension\OpenWithProgids"
  if ((Test-Path -LiteralPath $list) -and ((Get-Item -LiteralPath $list).GetValueNames() -contains $progId)) {
    Fail "$list still names $progId"
  }
}
Write-Host "ok: $appName and its file associations are gone"

Write-Host "Delivered: $appName and md2html, installed, opening a Markdown file, and uninstalled"
