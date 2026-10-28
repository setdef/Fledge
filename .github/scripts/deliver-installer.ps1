# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Delivery of a windowed app's NSIS installer (ADR 009) on Windows: the
# setup program fledge build wrote for examples/windowed_app, run as a
# person runs it, with nothing of Fledge or Ruby on this computer.
#
#   pwsh -NoProfile -File deliver-installer.ps1 -Installer INSTALLER
#
# INSTALLER is "Hello Window-x64-mingw-ucrt-setup.exe". It must carry the
# app's icon and version information. Installed silently (/S), as the
# person who runs it, with no administrator, it must put the app in
# %LOCALAPPDATA%\Programs\Hello Window, make a Start menu shortcut to it
# whose System.AppUserModel.ID, read back through the shell's
# IPropertyStore, is the app's identifier, make no desktop shortcut, and
# register an uninstaller under HKCU. Started from that shortcut, as the
# Start menu starts it, the app must write its report, which says it had
# no console and the AppUserModelID it gave itself: the shortcut's, which
# is what lets Windows show its notifications. Installed again over
# itself, as a new version would be, it must still be whole. Then its
# silent uninstaller must remove its files, its shortcut, and its
# registry key.

param(
  [Parameter(Mandatory)] [string] $Installer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$appName = 'Hello Window'
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
  Expect 'InstallLocation' $entry.InstallLocation $folder
  Expect 'UninstallString' $entry.UninstallString "`"$folder\uninstall.exe`""
  Expect 'QuietUninstallString' $entry.QuietUninstallString "`"$folder\uninstall.exe`" /S"
  Expect 'DisplayIcon' $entry.DisplayIcon $app
}

Install
CheckInstalled

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
Expect "the report's platform" $facts.platform 'x64-mingw-ucrt'
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

Write-Host "Delivered: $appName, installed and uninstalled"
