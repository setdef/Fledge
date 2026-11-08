# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of a windowed app's NSIS installer (ADR 009) on Windows: the
# setup program fledge build wrote for examples/windowed_app, run as a
# person runs it, with nothing of Fledge or Ruby on this computer.
#
#   pwsh -NoProfile -File deliver-installer.ps1 -Installer INSTALLER
#
# INSTALLER is "Hello Window-x64-mingw-ucrt-setup.exe". It must carry the
# app's icon and version information, and, run as a person runs it, show
# the app's license on its first page. Installed silently (/S), as the
# person who runs it, with no administrator, it must put the app in
# %LOCALAPPDATA%\Programs\Hello Window, make a Start menu shortcut to it
# whose System.AppUserModel.ID, read back through the shell's
# IPropertyStore, is the app's identifier, make no desktop shortcut, and
# register an uninstaller under HKCU, with the homepage as its links.
# Started from that shortcut, as the
# Start menu starts it, the app must write its report, which says it had
# no console and the AppUserModelID it gave itself: the shortcut's, which
# is what lets Windows show its notifications. What it opens must be in
# the registry, a file's in its extension's "Open with" list without
# taking its default, and opening a file and a folder through the shell
# must start the app with the path as its argument. Installed again over
# itself, as a new version would be, it must still be whole. Then its
# silent uninstaller must remove its files, its shortcut, and its
# registry keys.

param(
  [Parameter(Mandatory)] [string] $Installer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$appName = 'Hello Window'
# Hello Window-PLATFORM-setup.exe: x64-mingw-ucrt, or aarch64-mingw-ucrt (ADR 018).
$platform = [IO.Path]::GetFileNameWithoutExtension($Installer) -replace "^$appName-", '' -replace '-setup$', ''
$identifier = 'com.setdef.fledge.HelloWindow'

function Fail([string] $message) {
  Write-Host "::error::Delivery (installer): $message"
  exit 1
}

function Expect([string] $Label, $Actual, $Expected) {
  if ($Actual -cne $Expected) { Fail "$Label is '$Actual', not '$Expected'" }
  Write-Host "ok: $Label is $Expected"
}

# Waits up to $Seconds for $Condition to hold, as an uninstaller that
# copies itself to %TEMP% and starts again returns before it is done.
function WaitFor([scriptblock] $Condition, [string] $What, [int] $Seconds = 120) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  while (-not (& $Condition)) {
    if ((Get-Date) -gt $deadline) { Fail "$What did not happen within $Seconds seconds" }
    Start-Sleep -Milliseconds 500
  }
}

Add-Type -Namespace Fledge -Name Shell -MemberDefinition @'
[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
public static extern uint ExtractIconExW(string file, int index, System.IntPtr[] large, System.IntPtr[] small, uint count);

[StructLayout(LayoutKind.Sequential, Pack = 4)]
public struct PropertyKey { public System.Guid fmtid; public uint pid; }

[StructLayout(LayoutKind.Sequential)]
public struct PropVariant { public ushort vt; public ushort r1; public ushort r2; public ushort r3; public System.IntPtr value; public System.IntPtr value2; }

[ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPropertyStore {
  void GetCount(out uint count);
  void GetAt(uint index, out PropertyKey key);
  void GetValue(ref PropertyKey key, out PropVariant value);
  void SetValue(ref PropertyKey key, ref PropVariant value);
  void Commit();
}

[DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
public static extern void SHGetPropertyStoreFromParsingName(string path, System.IntPtr bindContext, int flags, ref System.Guid iid,
  [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);

[DllImport("ole32.dll")]
public static extern int PropVariantClear(ref PropVariant value);

// System.AppUserModel.ID (propkey.h): {9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}, 5, a VT_LPWSTR.
public static string AppUserModelId(string path) {
  System.Guid iid = new System.Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
  IPropertyStore store;
  SHGetPropertyStoreFromParsingName(path, System.IntPtr.Zero, 0, ref iid, out store);
  PropertyKey key = new PropertyKey { fmtid = new System.Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };
  PropVariant value;
  store.GetValue(ref key, out value);
  string id = value.vt == 31 ? Marshal.PtrToStringUni(value.value) : null;
  PropVariantClear(ref value);
  return id;
}

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
// when it is given (SEE_MASK_CLASSNAME, 0x1), waiting for the shell to
// start it (SEE_MASK_NOASYNC, 0x100), with no dialog on an error
// (SEE_MASK_FLAG_NO_UI, 0x400). The shell's folder handlers are COM
// objects that need a single-threaded apartment, which PowerShell's own
// thread is not, so it runs on one of its own, for at most a minute.
// Returns null, or why it failed.
public static string Open(string file, string verb, string className) {
  string result = "it did not return within a minute";
  System.Threading.Thread thread = new System.Threading.Thread(() => {
    ShellExecuteInfo info = new ShellExecuteInfo();
    info.size = Marshal.SizeOf(info);
    info.mask = 0x500u | (className == null ? 0u : 0x1u);
    info.verb = verb; info.file = file; info.className = className; info.show = 1;
    result = ShellExecuteExW(ref info) ? null : new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()).Message;
  });
  thread.IsBackground = true;
  thread.SetApartmentState(System.Threading.ApartmentState.STA);
  thread.Start();
  thread.Join(60000);
  return result;
}

[DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
public static extern int AssocQueryStringW(uint flags, int what, string association, string verb, System.Text.StringBuilder output, ref uint length);

// The command the shell runs for verb on association (ASSOCSTR_COMMAND, 1).
public static string Command(string association, string verb) {
  System.Text.StringBuilder output = new System.Text.StringBuilder(2048);
  uint length = 2048;
  return AssocQueryStringW(0, 1, association, verb, output, ref length) == 0 ? output.ToString() : null;
}
'@

$Installer = (Resolve-Path -LiteralPath $Installer).Path

# The setup program's own identity, which Explorer and the UAC prompt show.
$info = (Get-Item -LiteralPath $Installer).VersionInfo
Expect "the installer's FileDescription" $info.FileDescription "$appName Setup"
Expect "the installer's ProductName" $info.ProductName $appName
Expect "the installer's ProductVersion" $info.ProductVersion '1.2.3'
Expect "the installer's CompanyName" $info.CompanyName 'setdef'
Expect "the installer's version numbers" "$($info.FileMajorPart).$($info.FileMinorPart).$($info.FileBuildPart).$($info.FilePrivatePart)" '1.2.3.0'
if ([Fledge.Shell]::ExtractIconExW($Installer, -1, $null, $null, 0) -lt 1) { Fail 'the installer has no icon' }
Write-Host 'ok: the installer has an icon'

# The license page (fledge.yml's license_file), the first page a person
# sees: started without /S, the setup program's window holds a rich edit
# control whose text, read back with WM_GETTEXT, is the example's license.
# Nothing is installed before the page is accepted, so closing it here
# leaves the computer as it was.
Add-Type -Namespace Fledge -Name Window -MemberDefinition @'
public delegate bool EnumProc(System.IntPtr window, System.IntPtr data);
[DllImport("user32.dll")]
public static extern bool EnumChildWindows(System.IntPtr parent, EnumProc proc, System.IntPtr data);
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern int GetClassNameW(System.IntPtr window, System.Text.StringBuilder name, int size);
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern System.IntPtr SendMessageW(System.IntPtr window, uint message, System.IntPtr wParam, System.Text.StringBuilder lParam);
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern System.IntPtr SendMessageW(System.IntPtr window, uint message, System.IntPtr wParam, System.IntPtr lParam);

public static string RichEditText(System.IntPtr top) {
  string found = null;
  EnumChildWindows(top, delegate (System.IntPtr child, System.IntPtr data) {
    var name = new System.Text.StringBuilder(256);
    GetClassNameW(child, name, name.Capacity);
    if (!name.ToString().StartsWith("RichEdit")) return true;
    int length = SendMessageW(child, 0x000E, System.IntPtr.Zero, System.IntPtr.Zero).ToInt32();
    var text = new System.Text.StringBuilder(length + 1);
    SendMessageW(child, 0x000D, new System.IntPtr(length + 1), text);
    found = text.ToString();
    return false;
  }, System.IntPtr.Zero);
  return found;
}
'@
$setup = Start-Process -FilePath $Installer -PassThru
try {
  $licenseText = $null
  $deadline = (Get-Date).AddSeconds(60)
  while (-not $licenseText) {
    if ((Get-Date) -gt $deadline) { Fail 'the setup program showed no license page within 60 seconds' }
    Start-Sleep -Milliseconds 500
    $setup.Refresh()
    if ($setup.HasExited) { Fail "the setup program exited with $($setup.ExitCode) before it showed its license page" }
    if ($setup.MainWindowHandle -ne [IntPtr]::Zero) { $licenseText = [Fledge.Window]::RichEditText($setup.MainWindowHandle) }
  }
  $lines = @($licenseText -split "`r`n|`r|`n")
  Expect "the license page's first line" $lines[0] 'MIT No Attribution'
  Expect "the license page's copyright line" $lines[2] "Copyright $([char]0xA9) 2026 setdef"
  Write-Host "ok: the setup program's window '$($setup.MainWindowTitle)' shows the license first"
} finally {
  if (-not $setup.HasExited) { Stop-Process -Id $setup.Id -Force; $setup.WaitForExit() }
}

$folder = Join-Path $env:LOCALAPPDATA "Programs\$appName"
$app = Join-Path $folder "$appName.exe"
$startMenu = [Environment]::GetFolderPath('Programs')
$shortcut = Join-Path $startMenu "$appName.lnk"
$desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) "$appName.lnk"
$key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$identifier"
if (Test-Path -LiteralPath $folder) { Fail "$folder is there before the install" }

# The runner has Rubies; the installer and the app see only Windows'.
$system = $env:SystemRoot
$env:PATH = "$system\System32;$system;$system\System32\Wbem;$system\System32\WindowsPowerShell\v1.0"
if (Get-Command ruby -ErrorAction SilentlyContinue) { Fail "Get-Command still finds a Ruby on $env:PATH" }

function Install {
  $process = Start-Process -FilePath $Installer -ArgumentList '/S' -Wait -PassThru
  Expect 'the silent install exit status' $process.ExitCode 0
}

function CheckInstalled {
  if (-not (Test-Path -LiteralPath $app -PathType Leaf)) { Fail "$app is not installed" }
  if (-not (Test-Path -LiteralPath (Join-Path $folder 'uninstall.exe') -PathType Leaf)) { Fail 'there is no uninstall.exe' }
  if (-not (Test-Path -LiteralPath (Join-Path $folder 'app\main.rb'))) { Fail 'the app folder is not installed' }
  Write-Host "ok: $appName is installed in $folder"

  if (-not (Test-Path -LiteralPath $shortcut)) { Fail "there is no Start menu shortcut at $shortcut" }
  $link = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
  Expect "the shortcut's target" $link.TargetPath $app
  Expect "the shortcut's System.AppUserModel.ID" ([Fledge.Shell]::AppUserModelId($shortcut)) $identifier
  $shell = New-Object -ComObject Shell.Application
  $item = $shell.NameSpace($startMenu).ParseName("$appName.lnk")
  Expect "the shell's System.AppUserModel.ID of the shortcut" $item.ExtendedProperty('System.AppUserModel.ID') $identifier
  if (Test-Path -LiteralPath $desktop) { Fail 'a silent install made a desktop shortcut, which is off by default' }
  Write-Host 'ok: no desktop shortcut'

  $entry = Get-ItemProperty -LiteralPath $key
  Expect 'DisplayName' $entry.DisplayName $appName
  Expect 'DisplayVersion' $entry.DisplayVersion '1.2.3'
  Expect 'Publisher' $entry.Publisher 'setdef'
  Expect 'URLInfoAbout' $entry.URLInfoAbout 'https://github.com/setdef/Fledge'
  Expect 'HelpLink' $entry.HelpLink 'https://github.com/setdef/Fledge'
  Expect 'InstallLocation' $entry.InstallLocation $folder
  Expect 'UninstallString' $entry.UninstallString "`"$folder\uninstall.exe`""
  Expect 'QuietUninstallString' $entry.QuietUninstallString "`"$folder\uninstall.exe`" /S"
  Expect 'DisplayIcon' $entry.DisplayIcon $app
}

Install
CheckInstalled

# What the app opens (fledge.yml's file_associations; ADR 032, section 3),
# read back from the registry and through the shell's own API, and then
# opened as the shell opens them, in a folder whose name has a space and
# a character outside ASCII. A file's ProgID is in its extension's
# OpenWithProgids, its "Open with" list, and the extension's default is
# left alone; every folder gets a verb. Each passes the path as the
# program's one argument, as a file or folder dropped on the program
# does with nothing registered: the app writes its report to that path,
# or into it when it is a folder.
$classes = 'HKCU:\Software\Classes'
$progId = "$identifier.2"
$command = "`"$app`" `"%1`""
$extension = Get-Item -LiteralPath "$classes\.hellowindow"
Expect 'the default of .hellowindow' $extension.GetValue('') $null
Expect ".hellowindow's OpenWithProgids" ((Get-Item -LiteralPath "$classes\.hellowindow\OpenWithProgids").GetValueNames() -join ',') $progId
Expect "$progId's name" (Get-Item -LiteralPath "$classes\$progId").GetValue('') 'Hello Window report'
Expect "$progId's command" (Get-Item -LiteralPath "$classes\$progId\shell\open\command").GetValue('') $command
Expect "the folders' verb" (Get-Item -LiteralPath "$classes\Directory\shell\$identifier").GetValue('') 'Open with Hello Window'
Expect "the shell's command for $progId" ([Fledge.Shell]::Command($progId, 'open')) $command
Expect "the shell's command for the folders' verb" ([Fledge.Shell]::Command('Directory', $identifier)) $command

$dropped = Join-Path $env:RUNNER_TEMP 'Ein Ordner ü'
New-Item -ItemType Directory -Force $dropped | Out-Null
$document = Join-Path $dropped 'dropped.hellowindow'
Set-Content -LiteralPath $document -Value 'a document'
$failed = [Fledge.Shell]::Open($document, 'open', $progId)
if ($failed) { Fail "the shell could not open $document with ${progId}: $failed" }
WaitFor { (Get-Content -LiteralPath $document -Raw) -match '"ruby":"4.0.9"' } 'the app writing its report over the file the shell opened with it' 60
Write-Host "ok: the shell opened $document with the app, which got its path"
$failed = [Fledge.Shell]::Open($dropped, $identifier, 'Directory')
if ($failed) { Fail "the shell could not open $dropped with the folders' verb: $failed" }
WaitFor { Test-Path -LiteralPath (Join-Path $dropped 'hello_window.json') } 'the app writing its report into the folder the shell opened with it' 60
Write-Host "ok: the shell opened $dropped with the folders' verb, and the app got its path"
Remove-Item -LiteralPath (Join-Path $dropped 'hello_window.json')
Start-Process -FilePath $app -ArgumentList "`"$dropped`"" -Wait
if (-not (Test-Path -LiteralPath (Join-Path $dropped 'hello_window.json'))) { Fail 'the app given a folder, as a drop gives it, did not write into it' }
Write-Host 'ok: the installed app, started with a folder as a drop on it starts it, got its path'
Start-Sleep -Seconds 3

# Started from its Start menu shortcut, through the shell, as a click in
# the Start menu starts it. Given no arguments, it writes its report to
# its temporary folder (Ruby's Dir.tmpdir: TMPDIR, TMP, or TEMP), here a
# folder of this script's own, since setup-ruby points TMPDIR elsewhere.
$temporary = Join-Path $env:RUNNER_TEMP 'from the shortcut'
New-Item -ItemType Directory -Force $temporary | Out-Null
$env:TMPDIR = $temporary
$env:TMP = $temporary
$env:TEMP = $temporary
$report = Join-Path $temporary 'hello_window.json'
Remove-Item -LiteralPath $report -ErrorAction SilentlyContinue
Start-Process -FilePath $shortcut
WaitFor { Test-Path -LiteralPath $report } 'the app writing its report after starting from its shortcut' 60
Start-Sleep -Seconds 3
$facts = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
Expect "the report's Ruby" $facts.ruby '4.0.9'
Expect "the report's platform" $facts.platform $platform
Expect 'whether it had a console' $facts.console $false
Expect 'the AppUserModelID the app gave itself, which its shortcut carries' $facts.app_user_model_id ([Fledge.Shell]::AppUserModelId($shortcut))

# Whether Windows takes the app's notifications: a toast shown through a
# notifier for the AppUserModelID of the installed shortcut, by Windows
# PowerShell, which can call WinRT. A Windows that shows no notifications
# at all, such as a server with no one signed in, may refuse, which is
# reported, not failed: what the app needs of its installer is the
# shortcut's AppUserModelID, checked above.
$toast = @"
try {
  `$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
  `$null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
  `$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('$identifier')
  `$content = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText01)
  `$null = `$content.GetElementsByTagName('text').Item(0).AppendChild(`$content.CreateTextNode('Delivered by Fledge'))
  `$notifier.Show([Windows.UI.Notifications.ToastNotification]::new(`$content))
  "Windows took a toast from it (the notifier's setting: `$(`$notifier.Setting))"
} catch {
  "Windows could not say (`$(`$_.Exception.Message))"
}
"@
$setting = & "$system\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command $toast 2>&1
Write-Host "Notifications from ${identifier}: $setting"

# A new version installs over the old one: the old one's uninstaller runs
# first, and the app is whole again.
Install
CheckInstalled

$process = Start-Process -FilePath (Join-Path $folder 'uninstall.exe') -ArgumentList '/S' -Wait -PassThru
Expect 'the silent uninstall exit status' $process.ExitCode 0
WaitFor { -not (Test-Path -LiteralPath $folder) } "$folder going away"
Write-Host "ok: $folder is gone"
if (Test-Path -LiteralPath $shortcut) { Fail 'the Start menu shortcut is still there' }
Write-Host 'ok: the Start menu shortcut is gone'
if (Test-Path -LiteralPath $key) { Fail "$key is still in the registry" }
Write-Host "ok: $key is gone"
foreach ($left in "$classes\$progId", "$classes\.hellowindow", "$classes\Directory\shell\$identifier") {
  if (Test-Path -LiteralPath $left) { Fail "$left is still in the registry" }
}
Write-Host 'ok: the file associations are gone'

Write-Host "Delivered: $appName, installed and uninstalled"
